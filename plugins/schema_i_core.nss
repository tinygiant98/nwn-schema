
#include "util_i_debug"

const int SCHEMA_DRAFT_4 = 1;
const int SCHEMA_DRAFT_6 = 2;
const int SCHEMA_DRAFT_7 = 3;
const int SCHEMA_DRAFT_2019_09 = 4;
const int SCHEMA_DRAFT_2020_12 = 5;
const int SCHEMA_DRAFT_LATEST = SCHEMA_DRAFT_2020_12;

const string SCHEMA_DEFAULT_DRAFT = "https://json-schema.org/draft/2020-12/schema";
const string SCHEMA_DEFAULT_OUTPUT = "https://json-schema.org/draft/2020-12/output/schema";

const string SCHEMA_DB_SYSTEM = "schema_system";
const string SCHEMA_DB_USER = "schema_user";
const string SCHEMA_DB_TEST = "schema_test";

/// @todo
///     [ ] What do I do with this?  Numbering/nDraft without using constants?  Default (last)?
json jaSchemaDrafts = JsonParse(r"[
    ""http://json-schema.org/draft-04/schema#"",
    ""http://json-schema.org/draft-06/schema#"",
    ""http://json-schema.org/draft-07/schema#"",
    ""https://json-schema.org/draft/2019-09/schema"",
    ""https://json-schema.org/draft/2020-12/schema""
];");

json joScopes = JsonParse(r"{
    ""SCHEMA_SCOPE_LEXICAL"": [],
    ""SCHEMA_SCOPE_DYNAMIC"": [],
    ""SCHEMA_SCOPE_SCHEMA"": """",
    ""SCHEMA_SCOPE_SCHEMAPATH"", [],
    ""SCHEMA_SCOPE_INSTANCEPATH"": []
}");

/// @todo
///     [ ] Is there a way to remove these prototypes so they don't show up in the toolset editor?
///         [ ] schema_reference_ -> schema_core_ ? since it's used in a lot of places?
json schema_core_Validate(json jInstance, json joSchema);
json schema_reference_GetSchema(string sSchemaID);

/// @private Prepare a query for any schema-related database or for module use.
/// @param s The query string to prepare.
/// @param bForceModule If TRUE, the query is prepared for the module database.
/// @param sDatabase The database to prepare the query for.
sqlquery schema_core_PrepareQuery(string s, int bForceModule = TRUE, string sDatabase = SCHEMA_DB_USER)
{
    if (bForceModule)
        return SqlPrepareQueryObject(GetModule(), s);
    else
        return SqlPrepareQueryCampaign(sDatabase, s);
}

sqlquery schema_core_PrepareSystemQuery(string s)
{
    return schema_core_PrepareQuery(s, FALSE, SCHEMA_DB_SYSTEM);
}

sqlquery schema_core_PrepareUserQuery(string s)
{
    return schema_core_PrepareQuery(s, FALSE, SCHEMA_DB_USER);
}

sqlquery schema_core_PrepareTestQuery(string s)
{
    return schema_core_PrepareQuery(s, FALSE, SCHEMA_DB_TEST);
}

void schema_core_CreateTables()
{
    /// @note This table is built in both the administrative and user databases. This allows
    ///     queries written for user-based schema to be used against the admin database in the
    ///     event that the user database is not available.  Generated columns are used to
    ///     provde quick access to the $id for indexing purposes and other important values
    ///     for use in other systems, such as NUI forms.
    string s = r"
        CREATE TABLE IF NOT EXISTS schema_schema (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            schema TEXT NOT NULL,
            schema_id TEXT GENERATED ALWAYS AS (json_extract(schema, '$.$id')) STORED,
            schema_schema TEXT GENERATED ALWAYS AS (json_extract(schema, '$.$schema')) STORED,
            schema_title TEXT GENERATED ALWAYS AS (json_extract(schema, '$.title')) STORED,
            schema_description TEXT GENERATED ALWAYS AS (json_extract(schema, '$.description')) STORED,
            UNIQUE(schema_id) ON CONFLICT REPLACE
        );
    ";
    SqlStep(schema_core_PrepareUserQuery(s));
    SqlStep(schema_core_PrepareSystemQuery(s));

    s = r"
        CREATE INDEX IF NOT EXISTS schema_index ON schema_schema (schema_id);
    ;";
    SqlStep(schema_core_PrepareUserQuery(s));
    SqlStep(schema_core_PrepareSystemQuery(s));
}


/// -----------------------------------------------------------------------------------------------
///                                         SCOPE MANAGEMENT
/// -----------------------------------------------------------------------------------------------

/// @brief Scope management is accomplished via local variables set on the module object.  Scope
///     arrays track the various data required for each validation recursion, including the ability
///     track unique data for concurrent validation attempts.  Scope arrays are simulated-base-1, in
///     that the first array entry is an empty json value.
///
///        The depth value is used to track the concurrent validation attempts, which occur when
///     the system finds a valid schema in a location that cannot be consider validated, such as from
///     a file.  If the desired schema is found in a file, the system will attempt to validate the
///     provided schema before continuing with the instance validation.

/// @private Destroy all scope-associated local variables to ensure scope data from multiple
///     validations attempts does not collide.
void schema_scope_Destroy()
{
    DelayCommand(0.1, DeleteLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT"));
    DelayCommand(0.1, DeleteLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH"));

    json jaScopes = JsonObjectKeys(joScopes);
    int i; for (; i < JsonGetLength(jaScopes); i++)
        DelayCommand(0.1, DeleteLocalJson(GetModule(), JsonGetString(JsonArrayGet(jaScopes, i))));
}

/// @private Resize scope arrays to match the current scope depth.  If the array must grow,
///     new members are initialized to the default values in joScopes.
void schema_scope_ResizeArrays()
{
    int nRequiredLength = GetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH") + 1;

    json jaScopes = JsonObjectKeys(joScopes);
    int i; for (; i < JsonGetLength(jaScopes); i++)
    {
        string sScope = JsonGetString(JsonArrayGet(jaScopes, i));
        json joScope = GetLocalJson(GetModule(), sScope);
        if (JsonGetType(joScope) != JSON_TYPE_ARRAY)
            joScope = JsonArray();        
        
        int nLength = JsonGetLength(joScope);
        if (nLength == nRequiredLength)
            continue;
        else if (nLength > nRequiredLength)
            joScope = JsonArrayGetRange(joScope, 0, nRequiredLength);
        else if (nLength < nRequiredLength)
        {
            while (JsonGetLength(joScope) < nRequiredLength)
                joScope = JsonArrayInsert(joScope, JsonObjectGet(joScopes, sScope));
        }

        SetLocalJson(GetModule(), sScope, joScope);
    }
}

/// @private Get the current scope depth.
/// @param bDepthOnly If TRUE, only the depth is returned without initializing the scope arrays.
/// @returns The current scope depth, starting at 1.
/// @note The first array entry is an empty array. This construct allows for each initialization
///     of scope management arrays.
int schema_scope_GetDepth()
{
    int nDepth = GetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH");
    if (nDepth == 0)
    {
        SetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH", ++nDepth);
        schema_scope_ResizeArrays();
    }

    return nDepth;
}

/// @private Get the current scope data for the specified scope type.
/// @param sScope The scope type; SCHEMA_SCOPE_*
/// @returns A json array containing the data for the current scope depth.
json schema_scope_Get(string sScope)
{
    int nDepth = schema_scope_GetDepth();
    json jaScopes = GetLocalJson(GetModule(), sScope);
    if (JsonGetType(jaScopes) != JSON_TYPE_ARRAY || JsonGetLength(jaScopes) <= nDepth)
        return JsonArray();
    
    return JsonArrayGet(jaScopes, nDepth);
}

/// @private Convenience functions to retrieve scope data.
json schema_scope_GetLexical()      {return schema_scope_Get("SCHEMA_SCOPE_LEXICAL");}
json schema_scope_GetDynamic()      {return schema_scope_Get("SCHEMA_SCOPE_DYNAMIC");}
json schema_scope_GetSchema()       {return schema_scope_Get("SCHEMA_SCOPE_SCHEMA");}
json schema_scope_GetSchemaPath()   {return schema_scope_Get("SCHEMA_SCOPE_SCHEMAPATH");}
json schema_scope_GetInstancePath() {return schema_scope_Get("SCHEMA_SCOPE_INSTANCEPATH");}

/// @private Deconstruct a pointer string into an array of pointer segments.
/// @param sPointer The pointer string to deconstruct.
/// @returns A json array containing the path segments, or an empty json array if the path is empty.
json schema_scope_Deconstruct(string sPointer)
{
    string s = r"
        WITH RECURSIVE split_string(input_string, part, rest) AS (
            SELECT 
                TRIM(:pointer, '/'), 
                CASE 
                    WHEN INSTR(TRIM(:pointer, '/'), '/') = 0 
                        THEN TRIM(:pointer, '/')
                    ELSE SUBSTR(TRIM(:pointer, '/'), 1, INSTR(TRIM(:pointer, '/'), '/') - 1)
                END,
                CASE 
                    WHEN INSTR(TRIM(:pointer, '/'), '/') = 0 
                        THEN ''
                    ELSE SUBSTR(TRIM(:pointer, '/'), INSTR(TRIM(:pointer, '/'), '/') + 1)
                END
            
            UNION ALL
            
            SELECT 
                rest,
                CASE 
                    WHEN INSTR(rest, '/') = 0 
                        THEN rest
                    ELSE SUBSTR(rest, 1, INSTR(rest, '/') - 1)
                END,
                CASE 
                    WHEN INSTR(rest, '/') = 0 
                        THEN ''
                    ELSE SUBSTR(rest, INSTR(rest, '/') + 1)
                END
            FROM split_string
            WHERE rest != ''
        )
        SELECT json_group_array(part)
        FROM split_string
        WHERE part != '';
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":pointer", sPointer);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonArray();
}

/// @private Construct a pointer string from a json array of pointer segments.
/// @param jaPointer The json array containing the pointer segments.
/// @returns A string representing the pointer, or an empty string if the input is null or empty.
string schema_scope_Construct(json jaPointer = JSON_NULL)
{
    if (JsonGetType(jaPointer) != JSON_TYPE_ARRAY || JsonGetLength(jaPointer) == 0)
        return "";

    string s = r"
        WITH path_elements AS (
            SELECT value
            FROM json_each(:pointer)
        )
        SELECT 
            CASE 
                WHEN COUNT(*) = 0 THEN ''
                ELSE '/' || GROUP_CONCAT(value, '/')
            END AS path
        FROM path_elements;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":pointer", jaPointer);

    return SqlStep(q) ? SqlGetString(q, 0) : "";
}

/// @private Convenience function to construct pointer from lexical scope members.
string schema_scope_ConstructSchemaPath() {return schema_scope_Construct(schema_scope_GetSchemaPath());}
string schema_scope_ConstructInstancePath() {return schema_scope_Construct(schema_scope_GetInstancePath());}

/// @private Push a new item into the specified scope array at the current depth.
/// @param sScope Scope type SCHEMA_SCOPE_*; must be an array of arrays.
/// @param jItem The json object to push into the array.
void schema_scope_PushArrayItem(string sScope, json jItem)
{
    int nDepth = schema_scope_GetDepth();
    json jaScopes = GetLocalJson(GetModule(), sScope);
    
    if (JsonGetType(jaScopes) != JSON_TYPE_ARRAY)
        return;

    json jaScope = JsonArrayGet(jaScopes, nDepth);
    if (JsonGetType(jaScope) != JSON_TYPE_ARRAY)
        return;

    jaScope = JsonArrayInsert(jaScope, jItem);
    jaScopes = JsonArraySet(jaScopes, nDepth, jaScope);
    SetLocalJson(GetModule(), sScope, jaScopes);
}

/// @private Push a new item into the specified scope array at the current depth.
/// @param sScope Scope type SCHEMA_SCOPE_*; must be a simple array.
/// @param jItem The json object to push into the array.
void schema_scope_PushItem(string sScope, json jItem)
{
    json jaScope = GetLocalJson(GetModule(), sScope);
    if (JsonGetType(jaScope) != JSON_TYPE_ARRAY)
        return;

    SetLocalJson(GetModule(), sScope, JsonArraySet(jaScope, schema_scope_GetDepth(), jItem));
}

/// @private Convenience functions to modify scope arrays.
void schema_scope_PushLexical(json joScope)      {schema_scope_PushArrayItem("SCHEMA_SCOPE_LEXICAL", joScope);}
void schema_scope_PushDynamic(json joScope)      {schema_scope_PushArrayItem("SCHEMA_SCOPE_DYNAMIC", joScope);}
void schema_scope_PushSchemaPath(string sPath)   {schema_scope_PushArrayItem("SCHEMA_SCOPE_SCHEMAPATH", JsonString(sPath));}
void schema_scope_PushInstancePath(string sPath) {schema_scope_PushArrayItem("SCHEMA_SCOPE_INSTANCEPATH", JsonString(sPath));}

/// @todo
///      [ ] Structured logging error for missing sSchema?

/// @private Push a schema into the schema scope array.  If the schema is a known
///     json-schema.org draft, store the schema as its SCHEMA_DRAFT_* integer value.
/// @param sSchema The schema $id to push into the schema scope array.
void schema_scope_PushSchema(string sSchema)
{
    if (sSchema == "")
        return;

    string r = "^https?:\\/\\/json-schema\\.org\\/draft[-\\/](\\d*-?\\d*)\\/schema#?$";
    string sDraft = JsonGetString(JsonArrayGet(RegExpMatch(r, sSchema), 1));

    json jSchema;
    if      (sDraft == "04")      jSchema = JsonInt(SCHEMA_DRAFT_4);
    else if (sDraft == "06")      jSchema = JsonInt(SCHEMA_DRAFT_6);
    else if (sDraft == "07")      jSchema = JsonInt(SCHEMA_DRAFT_7);
    else if (sDraft == "2019-09") jSchema = JsonInt(SCHEMA_DRAFT_2019_09);
    else if (sDraft == "2020-12") jSchema = JsonInt(SCHEMA_DRAFT_2020_12);
    else                          jSchema = JsonString(sSchema);

    schema_scope_PushItem("SCHEMA_SCOPE_SCHEMA", jSchema);
}

/// @brief Remove the last member of a scope array ensuring the array length
///     matches current scope depth.
/// @param sScope Scope type; SCHEMA_SCOPE_*
void schema_scope_Pop(string sScope)
{
    int nDepth = schema_scope_GetDepth();

    json jaPaths = GetLocalJson(GetModule(), sScope);
    if (JsonGetType(jaPaths) != JSON_TYPE_ARRAY || JsonGetLength(jaPaths) <= nDepth)
        return;

    json jaPath = JsonArrayGet(jaPaths, nDepth);
    if (JsonGetType(jaPath) != JSON_TYPE_ARRAY)
        return;

    jaPaths = JsonArraySet(jaPaths, nDepth, (JsonGetLength(jaPath) == 1) ? JsonArray() : JsonArrayGetRange(jaPath, 0, -2));
    SetLocalJson(GetModule(), sScope, jaPaths);
}

/// @private Convenience functions to pop the last member from scope arrays.
void schema_scope_PopLexical()      {schema_scope_Pop("SCHEMA_SCOPE_LEXICAL");}
void schema_scope_PopDynamic()      {schema_scope_Pop("SCHEMA_SCOPE_DYNAMIC");}
void schema_scope_PopSchema()       {schema_scope_Pop("SCHEMA_SCOPE_SCHEMA");}
void schema_scope_PopSchemaPath()   {schema_scope_Pop("SCHEMA_SCOPE_SCHEMAPATH");}
void schema_scope_PopInstancePath() {schema_scope_Pop("SCHEMA_SCOPE_INSTANCEPATH");}

/// @private Increment the current scope depth by 1 and modify the scope arrays to handle
///     the additional depth.
void schema_scope_IncrementDepth()
{
    SetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH", schema_scope_GetDepth() + 1);
    schema_scope_ResizeArrays();
}

/// @private Decrement the current scope depth by 1 and resize the scope arrays to match
///     the new depth.
/// @note If the depth is already at 1, no changes are made.
void schema_scope_DecrementDepth()
{
    int nDepth = schema_scope_GetDepth();
    if (nDepth > 1)
    {
        SetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH", --nDepth);
        schema_scope_ResizeArrays();
    }
}

/// -----------------------------------------------------------------------------------------------
///                                         OUTPUT MANAGEMENT
/// -----------------------------------------------------------------------------------------------

/// @brief Output management functions provide functionality to recursively build the verbose
///    output of schema validation, as defined by json-schema.org.  This includes full validity,
///    error and annotations for each json object in the instance.  Functions are provided to pare
///    down the output to the user's desired verbosity level.

const string SCHEMA_OUTPUT_BASIC = "basic";
const string SCHEMA_OUTPUT_DETAILED = "detailed";
const string SCHEMA_OUTPUT_FLAG = "flag";
const string SCHEMA_OUTPUT_VERBOSE = "verbose";

string schema_output_GetErrorMessage(string sError, string sData = "")
{
    if (sError == "<validate_type>")
        return "instance does not match type";
    else if (sError == "<validate_enum>")
        return "instance not found in ";
    else if (sError == "<validate_minlength>")
        return "instance is shorter than minLength";
    else if (sError == "<validate_maxlength>")
        return "instance is longer than maxLength";
    else if (sError == "<validate_pattern>")
        return "instance does not match pattern";
    else if (sError == "<validate_minimum>")
        return "instance is less than minimum";
    else if (sError == "<validate_exclusiveminimum>")
        return "instance is not greater than exclusiveMinimum";
    else if (sError == "<validate_maximum>")
        return "instance is greater than maximum";
    else if (sError == "<validate_exlusivemaximum")
        return "instance is not less than exclusiveMaximum";
    else if (sError == "<validate_multipleof>")
        return "instance is not a multiple of multipleOf";
    else if (sError == "<validate_minitems>")
        return "instance length is less than minItems";
    else if (sError == "<validate_maxitems>")
        return "instance length is greater than maxItems";
    else if (sError == "<validate_uniqueitems>")
        return "instance items are not unique";
    else if (sError == "<validate_prefixitems>")
        return "<@todo>";
    else if (sError == "<validate_items>")
        return "<@todo>";
    else if (sError == "<validate_contains>")
        return "<@todo>";
    else if (sError == "<validate_mincontains")
        return "instace contains less than minContains";
    else if (sError == "<validate_maxcontains>")
        return "instance contains more than maxContains";
    else if (sError == "<validate_unevaluateditems>")
        return "<@todo>";
    else if (sError == "<validate_required>")
        return "instance missing required properties";
    else if (sError == "validate_minproperties>")
        return "instance has less than minProperties";
    else if (sError == "validate_maxproperties>")
        return "instance has more than maxProperties";
    else if (sError == "<validate_dependentrequired>")
        return "instance missing dependent property";
    else if (sError == "<validate_properties>")
        return "<@todo>";
    else if (sError == "<validate_patternproperties>")
        return "<@todo>";
    else if (sError == "<validate_additionalproperties>")
        return "<@todo>";
    else if (sError == "<validate_dependentschemas>")
        return "<@todo>";
    else if (sError == "<validate_propertynames>")
        return "instance property names do not match schema";
    else if (sError == "<validate_unevaluatedproperties>")
        return "<@todo>";
    else if (sError == "<validate_not>")
        return "instance matches not schema";
    else if (sError == "<validate_allof>")
        return "instance does not match all allOf schemas";
    else if (sError == "<validate_anyof>")
        return "instance does not match any anyOf schemas";
    else if (sError == "<validate_oneof>")
        return "instance does not match exactly one oneOf schema";
    else if (sError == "<validate_then>")
        return "instance valid against if but fails then";
    else if (sError == "<validate_else>")
        return "instance invalid against if but fails else";    
    else if (sError == "<validate_never>")
        return "instance never valid";
    
    else if (sError == "<instance_string>")
        return "instance must be a string";
    else if (sError == "<instance_number>")
        return "instance must be a number";
    else if (sError == "<instance_array>")
        return "instance must be an array";
    else if (sError == "<instance_object>")
        return "instance must be an object";
    
    return "";
}

int schema_output_GetValid(json joOutputUnit)
{
    return (JsonObjectGet(joOutputUnit, "valid") == JSON_TRUE);
}

json schema_output_SetValid(json joOutputUnit, int bValid = TRUE)
{
    return JsonObjectSet(joOutputUnit, "valid", bValid ? JSON_TRUE : JSON_FALSE);
}

/// @private Build a minimally acceptable output object for the desired verbosity level.  This
///     output object will not include any optional fields.  It relies on the json-schema.org
///     suggested validation output schema for draft 2020-12.  This schema must be packed in the
///     module file (or otherwise found by resman through the /development or other folder), and
///     can be downloaded from https://json-schema.org/draft/2020-12/output/schema.  The default
///     filename is output.txt, but can be any other valid filename if passed to the sFile argument.
/// @param sVerbosity The desired verbosity level: SCHEMA_OUTPUT_*
/// @param sFile The .txt file containing the output schema.
/// @returns A valid json object containing the minimal key:value pairs as defined by the output
///     schema at the desired verbosity level.  If no 'required' properties are found, an empty
///     json object is returned as this empty object has all 'required' properties and meets all
///     schema requirements.
/// @warning Although technically possible to replace this recommended output schema from json-schema.org
///     with a different schema, the replacement schema must conform to the general structure of
///     the json-schema.org output schema, including the use of the 'anyOf' keyword to handle
///     various verbosity levels, and the 'required' keyword to determine which key:value pairs
///     are minimally necessary.
/// @note This function is called constantly, therefore the results of the function are saved into
///     a local database for quicker retrieval.  Users that wish to reset the data, for events such
///     as metaschema updates, may reset all saved results using schema_core_Reset().
json schema_output_GetMinimalObject(string sVerbosity = SCHEMA_OUTPUT_VERBOSE, string sSchemaID = "")
{
    if (sVerbosity == "")
        sVerbosity = SCHEMA_OUTPUT_VERBOSE;

    /// @todo
    ///     [ ] testing only, revert.
    if (sSchemaID == "")
        sSchemaID = "output";
        //sSchemaID = SCHEMA_DEFAULT_OUTPUT;

    schema_core_CreateTables();

    string s = r"
        CREATE TABLE IF NOT EXISTS schema_output (
            verbosity TEXT NOT NULL,
            schema TEXT NOT NULL,
            output TEXT NOT NULL DEFAULT '{}',
            schema_id TEXT GENERATED ALWAYS AS (json_extract(schema, '$.$id')) STORED,
            PRIMARY KEY (verbosity, schema) ON CONFLICT REPLACE
        );
    ";
    SqlStep(schema_core_PrepareSystemQuery(s));

    /// @brief If previously built, the output unit at the desired verbosity level will
    ///     exist in the schema_output table.
    s = r"
        SELECT output
        FROM schema_output
        WHERE verbosity = :verbosity
            AND schema_id = :schema_id;
    ";
    sqlquery q = schema_core_PrepareSystemQuery(s);
    SqlBindString(q, ":verbosity", sVerbosity);
    SqlBindString(q, ":schema_id", sSchemaID);

    json joOutput = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    if (JsonGetType(joOutput) == JSON_TYPE_OBJECT)
        return joOutput;

    /// @brief If a stored output unit is not found, attempt to build it by retrieving
    ///     the base output schema from the schema database.  If the output schema
    ///     cannot be found in the schema database, schema_reference_GetSchema() will
    ///     attempt to load the schema from file <sSchemaID>.txt, if it exists.
    json joSchema = schema_reference_GetSchema(sSchemaID);
    if (JsonGetType(joSchema) == JSON_TYPE_NULL)
        return JsonObject();

    s = r"
        WITH RECURSIVE
            input_data AS (
                SELECT 
                    :schema AS schema,
                    :verbosity AS verbosity
                ),
            ref_path AS (
                SELECT json_extract(value, '$.$ref') AS path
                FROM input_data, 
                    json_each(json_extract(schema, '$.anyOf'))
                WHERE json_extract(value, '$.$ref') LIKE '%' || verbosity || '%'
                LIMIT 1
            ),
            ref_to_path AS (
                SELECT 
                    CASE
                        WHEN path LIKE '#/%' THEN '$.' || replace(substr(path, 3), '/', '.')
                        WHEN path = '#' THEN '$'
                        ELSE NULL
                    END AS sqlite_path
                FROM ref_path
            ),
            schema_resolution(sqlite_path, schema_obj, depth) AS (
                SELECT 
                    sqlite_path,
                    json_extract(input_data.schema, sqlite_path) AS schema_obj,
                    1 AS depth
                FROM ref_to_path, input_data
            
                UNION ALL
            
                SELECT
                    CASE
                        WHEN json_extract(schema_obj, '$.$ref') LIKE '#/%' THEN 
                            '$.' || replace(substr(json_extract(schema_obj, '$.$ref'), 3), '/', '.')
                        WHEN json_extract(schema_obj, '$.$ref') = '#' THEN '$'
                        ELSE NULL
                    END AS next_sqlite_path,
                    json_extract(input_data.schema, 
                        CASE
                            WHEN json_extract(schema_obj, '$.$ref') LIKE '#/%' THEN 
                                '$.' || replace(substr(json_extract(schema_obj, '$.$ref'), 3), '/', '.')
                            WHEN json_extract(schema_obj, '$.$ref') = '#' THEN '$'
                            ELSE NULL
                        END
                    ) AS next_schema,
                    depth + 1
                FROM schema_resolution, input_data
                WHERE json_extract(schema_obj, '$.$ref') IS NOT NULL
            ),
            final_schema AS (
                SELECT schema_obj
                FROM schema_resolution
                WHERE json_extract(schema_obj, '$.$ref') IS NULL
                ORDER BY depth DESC
                LIMIT 1
            ),
            required_props AS (
                SELECT value AS prop_name
                FROM final_schema, 
                    json_each(json_extract(schema_obj, '$.required'))
                ),
                prop_types AS (
                SELECT 
                    prop_name,
                    COALESCE(
                        json_extract(json_extract(final_schema.schema_obj, '$.properties.' || prop_name), '$.type'),
                            'object'
                    ) AS prop_type
                FROM required_props, final_schema
            )
        SELECT json_group_object(
            prop_name,
            CASE prop_type
                WHEN 'boolean' THEN true
                WHEN 'string'  THEN json_quote('')
                WHEN 'number'  THEN 0
                WHEN 'integer' THEN 0
                WHEN 'array'   THEN json_array()
                WHEN 'object'  THEN json_object()
                ELSE null
            END
        )
        FROM prop_types;
    ";

    q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":verbosity", sVerbosity);
    SqlBindJson(q, ":schema", joSchema);
    
    if (SqlStep(q))
    {
        json jOutput = SqlGetJson(q, 0);
        if (JsonGetType(jOutput) != JSON_TYPE_OBJECT)
            return JsonObject();

        string s = r"
            INSERT INTO schema_output (verbosity, schema, output)
            VALUES (:verbosity, :schema, :output)
            ON CONFLICT(verbosity, schema) DO UPDATE SET
                output = :output;
        ";
        sqlquery q = schema_core_PrepareSystemQuery(s);
        SqlBindString(q, ":verbosity", sVerbosity);
        SqlBindJson(q, ":schema", joSchema);
        SqlBindJson(q, ":output", jOutput);

        SqlStep(q);
        return jOutput;
    }

    return JsonObject();
}

json schema_output_SetKeywordLocation(json joOutputUnit)
{
    return JsonObjectSet(joOutputUnit, "keywordLocation", JsonString(schema_scope_ConstructSchemaPath()));
}

json schema_output_SetInstanceLocation(json joOutputUnit)
{
    return JsonObjectSet(joOutputUnit, "instanceLocation", JsonString(schema_scope_ConstructInstancePath()));
}

json schema_output_SetAbsoluteKeywordLocation(json joOutputUnit)
{
    /// @todo
    ///      [ ] Need the functionality to build the absolute keyword pointer
    return JsonObjectSet(joOutputUnit, "absoluteKeywordLocation", JsonString("@todo"));
}

/// @private Build an output unit skeleton.  keywordLocation and instanceLocation are populated here
///     for use by parent nodes.  Child nodes will have these values overwritten as annotations and
///     errors are added.
/// @note keyword valid is set to TRUE here even though the query in schema_output_GetMinimalObject()
///     specifies a value of `true` as the value is sometimes translated to integer 1 and no longer
///     recognized as boolean for comparison purposes.
json schema_output_GetOutputUnit()
{
    json joOutputUnit = schema_output_GetMinimalObject();
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);
    joOutputUnit = schema_output_SetValid(joOutputUnit, TRUE);

    return joOutputUnit;
}

/// @private Insert an error object into the parent node's errors array.
json schema_output_InsertParentError(json joOutputUnit, json joError)
{
    if (JsonGetType(joError) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    if (JsonGetType(jaErrors) != JSON_TYPE_ARRAY)
        jaErrors = JsonArray();

    jaErrors = JsonArrayInsert(jaErrors, joError);
    joOutputUnit = JsonObjectSet(joOutputUnit, "errors", jaErrors);
    joOutputUnit = schema_output_SetValid(joOutputUnit, FALSE);

    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joOutputUnit); 
    return joOutputUnit;
}

/// @private Insert an annotation object into the parent node's annotations array.
json schema_output_InsertParentAnnotation(json joOutputUnit, json joAnnotation)
{
    if (JsonGetType(joAnnotation) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaAnnotations = JsonObjectGet(joOutputUnit, "annotations");
    if (JsonGetType(jaAnnotations) != JSON_TYPE_ARRAY)
        jaAnnotations = JsonArray();

    jaAnnotations = JsonArrayInsert(jaAnnotations, joAnnotation);
    joOutputUnit = JsonObjectSet(joOutputUnit, "annotations", jaAnnotations);

    json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    int bValid = JsonGetType(jaErrors) == JSON_TYPE_ARRAY && JsonGetLength(jaErrors) > 0;
        
    joOutputUnit = schema_output_SetValid(joOutputUnit, !bValid);
    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joOutputUnit); 

    return joOutputUnit;
}

/// @todo
///     [ ] how do we handle failed keyword validations that may not fail the entire schema?

/// @private Insert an error string in an output unit.
json schema_output_InsertChildError(json joOutputUnit, string sError)
{
    joOutputUnit = JsonObjectSet(joOutputUnit, "error", JsonString(sError));
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);

    return schema_output_SetValid(joOutputUnit, FALSE);
}

/// @private Insert an annotation key:value pair into an output unit.
json schema_output_InsertChildAnnotation(json joOutputUnit, string sKey, json jValue)
{
    joOutputUnit = JsonObjectSet(joOutputUnit, sKey, jValue);
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);

    return schema_output_SetValid(joOutputUnit, TRUE);
}

/// @private Reduce a verbose output unit to a flag.
json schema_output_Flag(json joOutputUnit)
{
    if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
        return JSON_NULL;

    /// @todo
    ///     [ ] This JsonFind won't work, need the key array
    if (JsonFind(joOutputUnit, JsonString("valid")) == JsonNull())
        return JSON_NULL;

    return JsonObjectSet(JsonObject(), "valid", JsonObjectGet(joOutputUnit, "valid"));
}

/// @private Reduce a verbose output unit to a list of errors without nested context.
json schema_output_Basic(json joOutputUnit)
{
    if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
        return JSON_NULL;

    string s = r"
        WITH 
            output(data) AS (
                SELECT :output
            ),
            output_tree AS (
                SELECT * FROM output, json_tree(output.data)
            ),
            output_errors AS (
                SELECT DISTINCT parent.path, parent.value
                FROM output_tree AS parent
                JOIN output_tree AS child
                    ON child.parent = parent.id
                WHERE parent.type = 'object'
                AND child.key = 'error'
            ),
            output_filter AS (
                SELECT path, json_remove(value, '$.annotations') AS value
                FROM output_errors
            )
        SELECT
            CASE
                WHEN json_array_length(COALESCE(json_group_array(output_filter.value), '[]')) > 0
                    THEN json_object('valid', false, 'errors', json_group_array(output_filter.value))
                ELSE
                    json_object('valid', true)
            END
        FROM output_filter;
    ";

    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":output", joOutputUnit);

    return SqlStep(q) ? SqlGetJson(q, 0) : JSON_NULL;
}

/// @todo this output still needs work to remove any valid results entries as well as
///       collapsing/removing as required by json-schema.org
json schema_output_Detailed(json joOutputUnit)
{
    if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
        return JSON_NULL;

    string s = r"
        WITH
        output(data) AS (
            SELECT :output
        ),
        output_tree AS (
            SELECT * FROM output, json_tree(output.data)
        ),
        output_valid AS (
            SELECT DISTINCT parent
            FROM output_tree
            WHERE key = 'valid' 
            AND value = 1
        ),
        output_filtered AS (
            SELECT *,
                ROW_NUMBER() OVER (ORDER BY id) AS row_num
            FROM output_tree
            WHERE fullkey NOT LIKE '%.annotations%'
            AND id NOT IN (SELECT parent FROM output_valid)
            AND parent NOT IN (SELECT parent FROM output_valid)
        ),
        output_folded AS (
            SELECT
            row_num,
            json_object() AS output
            FROM output_filtered
            WHERE row_num = 1

            UNION ALL

            SELECT
            nr.row_num,
            json_set(
                pr.output,
                nr.fullkey,
                CASE
                WHEN nr.type = 'object' THEN json_object()
                    WHEN nr.type = 'array' THEN json_array()
                    ELSE nr.value
                END
            ) AS output
            FROM output_filtered nr
            JOIN output_folded pr
            ON nr.row_num = pr.row_num + 1
        )
        SELECT result
        FROM output_folded
        WHERE row_num = (SELECT MAX(row_num) FROM output_folded);}
    ";

    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":output", joOutputUnit);

    return SqlStep(q) ? SqlGetJson(q, 0) : JSON_NULL;
}

/// -----------------------------------------------------------------------------------------------
///                                     REFERENCE MANAGEMENT
/// -----------------------------------------------------------------------------------------------
/// @brief Schema reference management functions.  These functions provide a method for identifying,
///     resolving and utilizing $anchor, $dynamicAnchor, $ref and $dynamicRef keywords.

/// @todo
///     [x] Add functionality for reference keywords from previous schema drafts.
///     [ ] Build documentation!

/// @private Normalize a path that contains empty segments, or hierarchical segments such as
///     "." and "..".
/// @param sPath The path to normalize.
/// @returns A normalized path string with empty segments and hierarchical segments resolved.
string schema_reference_NormalizePath(string sPath)
{
    json jaParts = schema_scope_Deconstruct(sPath); // Split path into array segments
    json jaStack = JsonArray(); // Initialize empty stack

    int i, n = JsonGetLength(jaParts);
    for (i = 0; i < n; i++)
    {
        string s = JsonGetString(JsonArrayGet(jaParts, i));
        if (s == "" || s == ".")
            continue;
        if (s == "..")
        {
            if (JsonGetLength(jaStack) > 0)
                jaStack = JsonArrayGetRange(jaStack, 0, -2); // Remove last segment
            continue;
        }
        jaStack = JsonArrayInsert(jaStack, JsonString(s), JsonGetLength(jaStack)); // Add to end
    }
    return schema_scope_Construct(jaStack); // Re-join segments into path string
}

json schema_reference_ResolveAnchor(json joSchema, string sAnchor)
{
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT || sAnchor == "")
        return JsonNull();

    string s = r"
        WITH
            schema(data) AS (SELECT :schema),
            schema_tree AS (SELECT * FROM schema, json_tree(schema.data)),
            schema_parent AS (
                SELECT parent
                FROM schema_tree
                WHERE key = '$anchor'
                AND atom = :anchor
            )
        SELECT value 
        FROM schema_tree 
        WHERE id = (SELECT parent from schema_parent);
    ";

    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindString(q, ":anchor", sAnchor);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
}

json schema_reference_ResolvePointer(json joSchema, string sPointer)
{
    string s = r"
        WITH
            schema(data) AS (SELECT :schema),
            schema_tree AS (SELECT * FROM schema, json_tree(schema.data)),
            schema_path AS (
                SELECT 
                    '$' || replace(
                        CASE WHEN substr(:pointer, 1, 1) = '/' 
                            THEN substr(:pointer, 2) 
                            ELSE :pointer 
                        END, 
                        '/', '.'
                    ) AS path
            )
        SELECT value
        FROM schema_tree 
        WHERE fullkey = (SELECT path FROM schema_path)
        LIMIT 1;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindString(q, ":pointer", sPointer);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
}

/// @private Remove a schema from the database by its ID.
/// @param sID The ID of the schema to remove.
/// @note If a schema file exists, this function does not delete that file.
void schema_reference_DeleteSchema(string sID)
{
    if (sID == "")
        return;

    schema_core_CreateTables();

    string s = r"
        DELETE FROM schema_schema
        WHERE schema_id = :schema_id;
    ";
    sqlquery q = schema_core_PrepareUserQuery(s);
    SqlBindString(q, ":schema_id", sID);

    SqlStep(q);
}

/// @private Add a validated schema to the database.
/// @param joSchema The json object representing the schema to save.
/// @warning This function should only be called after the schema has been validated.
///     Invalid schema objects may cause undefined or unexpected behavior.
void schema_reference_SaveSchema(json joSchema)
{
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
        return;

    schema_core_CreateTables();

    string sID = JsonGetString(JsonObjectGet(joSchema, "$id"));
    if (sID == "")
        return;

    string s = r"
        INSERT INTO schema_schema (schema)
        VALUES (:schema)
        ON CONFLICT(schema) DO UPDATE SET
            schema = :schema;
    ";
    sqlquery q = schema_core_PrepareUserQuery(s);
    SqlBindJson(q, ":schema", joSchema);

    SqlStep(q);
}

/// @todo
///     [ ] Track where these JsonNull() get returns and figure out what to do with them.
///     [ ] Add an annotation here if $schema = "" or could not be found in db.
///     [ ] Need better error handling/messaging here.  Structured logging?
///     [ ] Ensure $dynamicReference acts like $ref if the $dynamicAnchor can't be located.

json schema_reference_GetSchema(string sSchemaID)
{
    if (sSchemaID == "")
        return JsonNull();

    schema_core_CreateTables();

    string s = r"
        SELECT * 
        FROM schema_schema
        WHERE schema_id = :id
            OR schema_id = :id || '#';
    ";
    sqlquery q = schema_core_PrepareUserQuery(s);
    SqlBindString(q, ":id", sSchemaID);

    json joSchema = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
        return joSchema;

    /// @note Attempt to retrieve the schema from the admin table.
    q = schema_core_PrepareSystemQuery(s);
    SqlBindString(q, ":id", sSchemaID);

    joSchema = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
        return joSchema;

    /// @note Attempt to retrieve the schema from a ResMan file.
    if (GetStringLength(sSchemaID) <= 16 && ResManGetAliasFor(sSchemaID, RESTYPE_TXT) != "")
    {
        joSchema = JsonParse(ResManGetFileContents(sSchemaID, RESTYPE_TXT));
        if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
        {
            /// @todo
            ///     [ ] temporery for testing only, remove!
            if (sSchemaID == "output")
                return joSchema;

            /// @note File-sourced schema are not trusted, so validation must
            ///     be performed before saving the schema to the database.
            string sSchema = JsonGetString(JsonObjectGet(joSchema, "$schema"));
            if (sSchema == "")
                sSchema = SCHEMA_DEFAULT_DRAFT;

            json joMeta = schema_reference_GetSchema(sSchema);
            if (JsonGetType(joMeta) == JSON_TYPE_NULL && sSchema != SCHEMA_DEFAULT_DRAFT)
                joMeta = schema_reference_GetSchema(SCHEMA_DEFAULT_DRAFT);

            if (JsonGetType(joMeta) == JSON_TYPE_NULL)
                return JsonNull();
            else
            {
                schema_scope_IncrementDepth();
                json joResult = schema_core_Validate(joSchema, joMeta);
                schema_scope_DecrementDepth();

                if (schema_output_GetValid(joResult))
                {
                    schema_reference_SaveSchema(joSchema);
                    return joSchema;
                }
                else
                    return JsonNull();
            }
        }
    }

    return JsonNull();
}

/// @todo
///     [ ] Is this where we need ~0 and ~1 resolution?

/// @private Resolve a fragment reference within a $ref.
/// @param joSchema The base schema to resolve the fragment against.
/// @param sFragment The fragment string to resolve.
/// @returns The resolved fragment, or JsonNull() if the fragment
///     could not be resolved.
json schema_reference_ResolveFragment(json joSchema, string sFragment)
{
    if (GetStringLeft(sFragment, 1) == "/")
        return schema_reference_ResolvePointer(joSchema, sFragment);
    else
    {
        json joAnchor = schema_reference_ResolveAnchor(joSchema, sFragment);
        if (JsonGetType(joAnchor) == JSON_TYPE_NULL)
            joAnchor = JsonObjectGet(joSchema, sFragment);

        return joAnchor;
    }
}

string schema_reference_MergePath(json jaMatchBase, string sPathRef)
{
    if (JsonGetString(JsonArrayGet(jaMatchBase, 3)) != "" &&
        JsonGetString(JsonArrayGet(jaMatchBase, 5)) == "")
        return "/" + sPathRef;
    else
    {
        string sPathBase = JsonGetString(JsonArrayGet(jaMatchBase, 5));
        json jaMatch = RegExpMatch("^(.*\\/)", sPathBase);
        if (JsonGetType(jaMatch) != JSON_TYPE_NULL && jaMatch != JsonArray())
            return JsonGetString(JsonArrayGet(jaMatch, 1)) + sPathRef;
        else
            return sPathRef;
    }
}

/// @private Determine is members of jaMatch meet desired existence
///     criteria defined in jaCriteria.
/// @param jaMatch Uri-reference match results.
/// @param jaCriteria Existence criteria array.
/// @returns TRUE for a successful match, FALSE otherwise.
/// @note jaCriteria must be an 10-element array containing the integers
///     -1, 0 or 1.  No other values are valid.  This function will compare
///     each member in jaMatch to it's matching-index member in jaCriteria.
///         -1: Value of matching index is ignored
///          0: Value of matching index must be a zero-length string
///          1: Value of matching index must be a greater-than-zero-length string
int schema_reference_CheckMatch(json jaMatch, json jaCriteria)
{
    string s = r"
        WITH
            pairs AS (
                SELECT n,
                    json_extract(:match, '$[' || n || ']') AS t,
                    json_extract(:criteria, '$[' || n || ']') AS c
                FROM generate_series(0, json_array_length(:criteria) - 1) AS n
                WHERE json_extract(:criteria, '$[' || n || ']') != -1
            )
        SELECT
            CASE
                WHEN SUM(
                    CASE
                        WHEN c = 1 AND (t IS NULL OR t = '') THEN 1
                        WHEN c = 0 AND (t IS NOT NULL AND t != '') THEN 1
                        ELSE 0
                    END
                ) = 0
                THEN 1
                ELSE 0
            END AS result
        FROM pairs;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":match", jaMatch);
    SqlBindJson(q, ":criteria", jaCriteria);

    return SqlStep(q) ? SqlGetInt(q, 0) : FALSE;
}

/// @private Resolve a $ref.  This function follows closesly the uri resolution
///     algorithm defined in RFC 3986, Section 5.2.  It handles both absolute and
///     relative references, as well as fragment-only references.  Additionally, it
///     handles a special case where the absolute uri cannot be determined, so any
///     path, query or fragment segments can be used to load a stored schema or parse
///     a json file with the same name.
/// @param joSchema The base schema to resolve the reference against.
/// @param jsRef The $ref json object to resolve.
/// @returns The resolved schema, or the base schema if no resolution is possible.
json schema_reference_ResolveRef(json joSchema, json jsRef)
{
    string sRef = JsonGetString(jsRef);
    if (sRef == "" || sRef == "#")
        return joSchema;

    /// @note This regex and match definitions can be found in RFC 3896,
    ///     Appendix B.  This regex returns 9 matches in addition to the
    ///     base match.
    string r = "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?$";
    json jaMatchRef = RegExpMatch(r, sRef);

    /// @note Handle fragment-only references.  These references
    ///     should exist within the base schema (joSchema).
    if (schema_reference_CheckMatch(jaMatchRef, JsonParse("[-1,0,0,0,0,0,0,0,1,1]")))
        return schema_reference_ResolveFragment(joSchema, JsonGetString(JsonArrayGet(jaMatchRef, 9)));

    /// @note A resource's absolute uri is determined by RFC 3896, paragraph 5.1,
    ///     Appendix A (uri grammar), and Appendix B (parsing).  An absolute uri is
    ///     required if the uri fragment is relative.
    /// @note Find the absolute uri from either:
    ///     1) the absolute uri from the $ref
    ///     2) the absolute uri from the schema's $id
    ///     If neither of those two exists, an absolute uri cannot be determined
    ///         and further resolution is not possible.
    string sAbsoluteURI, sTargetURI;
    if (JsonGetType(jaMatchRef) != JSON_TYPE_NULL && jaMatchRef != JsonArray())
    {
        /// @note 1) the absolute uri from the $ref
        string s1 = JsonGetString(JsonArrayGet(jaMatchRef, 1));
        string s2 = JsonGetString(JsonArrayGet(jaMatchRef, 2));
        string s3 = JsonGetString(JsonArrayGet(jaMatchRef, 3));
        string s5 = JsonGetString(JsonArrayGet(jaMatchRef, 5));
        string s6 = JsonGetString(JsonArrayGet(jaMatchRef, 6));

        if (GetStringRight(s1, 1) == ":" && s2 != "")
            sAbsoluteURI = s1 + s3 + s5 + s6;
    }
    else
    {
        /// @note 2) the absolute uri from the schema's $id
        json jaMatchSchema = RegExpMatch(r, JsonGetString(JsonObjectGet(joSchema, "$id")));
        if (JsonGetType(jaMatchSchema) != JSON_TYPE_NULL && jaMatchSchema != JsonArray())
        {
            string s1 = JsonGetString(JsonArrayGet(jaMatchSchema, 1));
            string s2 = JsonGetString(JsonArrayGet(jaMatchSchema, 2));
            string s3 = JsonGetString(JsonArrayGet(jaMatchSchema, 3));
            string s5 = JsonGetString(JsonArrayGet(jaMatchSchema, 5));
            string s6 = JsonGetString(JsonArrayGet(jaMatchSchema, 6));

            if (GetStringRight(s1, 1) == ":" && s2 != "")
                sAbsoluteURI = s1 + s3 + s5 + s6;
        }
    }

    /// @note If the absolute uri is a self-reference, the analysis can be
    ///     simplified to the current schema and fragment resolution, if any.
    string sSchemaID = JsonGetString(JsonObjectGet(joSchema, "$id"));
    if (sSchemaID != "" && sAbsoluteURI == sSchemaID)
    {
        string sFragment = JsonGetString(JsonArrayGet(jaMatchRef, 9));
        if (sFragment != "")
            return schema_reference_ResolveFragment(joSchema, sFragment);
        else
            return joSchema;
    }

    /// @note Handle a special, non-specification, case:
    ///     - The absolute uri cannot be determined AND EITHER
    ///        1) The reference matches -> path [ "?" query ] [ "#" fragment ]
    ///             - Combine the path [ "?" query ] segments of the reference
    ///                 and attemp to load a stored schema or parse a json file
    ///                 with the same name
    ///
    ///        OR
    ///
    ///        2) The reference matches -> "?" query [ "#" fragment ]
    ///             - If the schema's $id property contains matches
    ///                 path [ "?" query ], parse the path and combine with the
    ///                 reference's query section, then attempt to load a stored schema
    ///                 of parse a json file with the same name
    if (sAbsoluteURI == "")
    {
        if (schema_reference_CheckMatch(jaMatchRef, JsonParse("[-1,0,0,0,0,1,-1,-1,-1,-1]")))
        {
            /// @note Reference matches -> path [ "?" query ] [ "#" fragment ] grammar.
            ///     Use path + query construct and attempt to load a stored schema or
            ///     parse a json file with the same name
            string sSchema = 
                JsonGetString(JsonArrayGet(jaMatchRef, 5)) +
                JsonGetString(JsonArrayGet(jaMatchRef, 6));

            json joSchema = (sSchema != "") ? schema_reference_GetSchema(sSchema) : JsonNull();
            if (JsonGetType(joSchema) == JSON_TYPE_NULL)
                return JsonNull();

            string sFragment = JsonGetString(JsonArrayGet(jaMatchRef, 9));
            if (sFragment != "")
                return schema_reference_ResolveFragment(joSchema, sFragment);
            else
                return joSchema;
        }
        else if (schema_reference_CheckMatch(jaMatchRef, JsonParse("[-1,0,0,0,0,0,1,1,-1,-1]")))
        {
            /// @note Reference matches -> "?" query [ "#" fragment ] grammar.  Check if the
            ///     schema's $id matches -> path [ "?" query ] grammar.  If so, use
            ///     schema.path + reference.query construct and attempt to load a stored
            ///     schema or parse a json file with the same name
            string sID = JsonGetString(JsonObjectGet(joSchema, "$id"));
            if (sID != "")
            {
                json jaMatch = RegExpMatch(r, sID);
                if (schema_reference_CheckMatch(jaMatch, JsonParse("[-1,0,0,0,0,1,-1,-1,-1,-1]")))
                {
                    string sSchema =
                        JsonGetString(JsonArrayGet(jaMatch, 5)) +
                        JsonGetString(JsonArrayGet(jaMatchRef, 6));

                    json joSchema = (sSchema != "") ? schema_reference_GetSchema(sSchema) : JsonNull();
                    if (JsonGetType(joSchema) == JSON_TYPE_NULL)
                        return JsonNull();

                    string sFragment = JsonGetString(JsonArrayGet(jaMatchRef, 9));
                    if (sFragment != "")
                        return schema_reference_ResolveFragment(joSchema, sFragment);
                    else
                        return joSchema;
                }
            }
        }

        /// @note The special case is not satisfied and the absolute uri cannot be resolved.  No
        ///     further resolution is possible.
        return JsonNull();
    }
    else
    {
        /// @note An absolute URI exists.  If this code is reached:
        ///     - reference is relative
        ///     - absolute uri has been resolved
        ///     The absolute uri must be rebuilt to include the relative portion of the
        ///         reference, including any query segment, without the fragment segment
        json jaMatchBase = RegExpMatch(r, sAbsoluteURI);
        if (JsonGetString(JsonArrayGet(jaMatchRef, 1)) != "")
        {
            sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 1));
            sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 3));
            sTargetURI += schema_reference_NormalizePath(JsonGetString(JsonArrayGet(jaMatchRef, 5)));
            sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6));
        }
        else
        {
            if (JsonGetString(JsonArrayGet(jaMatchRef, 3)) != "")
            {
                sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 3));
                sTargetURI += schema_reference_NormalizePath(JsonGetString(JsonArrayGet(jaMatchRef, 5)));
                sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6));
            }
            else
            {
                if (JsonGetString(JsonArrayGet(jaMatchRef, 5)) == "")
                {
                    sTargetURI += JsonGetString(JsonArrayGet(jaMatchBase, 5));
                    if (JsonGetString(JsonArrayGet(jaMatchRef, 6)) != "")
                        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6));
                    else
                        sTargetURI += JsonGetString(JsonArrayGet(jaMatchBase, 6));
                }
                else
                {
                    if (GetStringLeft(JsonGetString(JsonArrayGet(jaMatchRef, 5)), 1) == "/")
                        sTargetURI += schema_reference_NormalizePath(JsonGetString(JsonArrayGet(jaMatchRef, 5)));
                    else 
                    {
                        sTargetURI += schema_reference_MergePath(jaMatchBase, JsonGetString(JsonArrayGet(jaMatchRef, 5)));
                        sTargetURI = schema_reference_NormalizePath(sTargetURI);
                    }
                    sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6));
                }
                sTargetURI = JsonGetString(JsonArrayGet(jaMatchBase, 3)) + sTargetURI;
            }
            sTargetURI = JsonGetString(JsonArrayGet(jaMatchBase, 1)) + sTargetURI;
        }
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 8));
    }

    /// @note The absolute uri has been derived.  The schema source can be retrieved
    ///     and fragment, if any, resolved.
    json jaMatchTarget = RegExpMatch("^(.*?)#?(.*)$", sTargetURI);
    if (JsonGetType(jaMatchTarget) != JSON_TYPE_NULL && jaMatchTarget != JsonArray())
    {
        string sSchema = JsonGetString(JsonArrayGet(jaMatchTarget, 1));
        string sFragment = JsonGetString(JsonArrayGet(jaMatchTarget, 2));

        if (sSchema == "")
            return JsonNull();
        else
        {
            json joSchema = schema_reference_GetSchema(sSchema);
            if (JsonGetType(joSchema) == JSON_TYPE_NULL)
                return JsonNull();

            if (sFragment == "")
                return joSchema;
            else
                return schema_reference_ResolveFragment(joSchema, sFragment);
        }
    }

    return JsonNull();
}

/// @todo
///     [ ] See who is receiving the JsonNull() and handle it.
///     [ ] Do we need version guardrails here?  Maybe not, but for consistency?

/// @private Resolve a dynamic anchor subschema from the current dynamic scope.
/// @param jsRef The dynamic anchor to resolve.
/// @returns The resolved dynamic anchor schema as a json object, or an empty
///     json object if not found.
json schema_reference_ResolveDynamicRef(json joSchema, json jsRef)
{
    json jaDynamic = schema_scope_GetDynamic();
    if (JsonGetType(jaDynamic) != JSON_TYPE_ARRAY || JsonGetLength(jaDynamic) == 0)
        return JsonNull();

    json jaSchema = JsonArrayGet(jaDynamic, schema_scope_GetDepth());
    if (JsonGetType(jaSchema) != JSON_TYPE_OBJECT || JsonGetLength(jaSchema) == 0)
        return JsonNull();

    int i; for (i = JsonGetLength(jaSchema); i >= 1; i--)
    {
        json joScope = JsonArrayGet(jaSchema, i);
        json jsAnchor = JsonObjectGet(joScope, "$dynamicAnchor");
        if (JsonGetType(jsAnchor) == JSON_TYPE_STRING && jsAnchor == jsRef)
            return joScope;
    }

    /// @note If the $dynamicAnchor is not found in the current dynamic scope,
    ///     the $dynamicRef is treated as a $ref.
    return schema_reference_ResolveRef(joSchema, jsRef);
}

/// @ todo
///     [x] Convert this function to search for the value in the json_tree where
///         the fullkey matches the current lexical pointer and $recursiveAnchor = true

json schema_reference_ResolveRecursiveRef(json joSchema)
{
    json jaDynamic = schema_scope_GetDynamic();
    if (JsonGetType(jaDynamic) != JSON_TYPE_ARRAY || JsonGetLength(jaDynamic) == 0)
        return JsonNull();

    json jaSchema = JsonArrayGet(jaDynamic, schema_scope_GetDepth());
    if (JsonGetType(jaSchema) != JSON_TYPE_OBJECT || JsonGetLength(jaSchema) == 0)
        return JsonNull();

    int i; for (i = 1; i <= JsonGetLength(jaSchema); i++)
    {
        json joScope = JsonArrayGet(jaSchema, i);
        json jsAnchor = JsonObjectGet(joScope, "$recursiveAnchor");
        if (JsonGetType(jsAnchor) == JSON_TYPE_BOOL && jsAnchor == JSON_TRUE)
            return joScope;
    }

    /// @note If the $recursiveAnchor is not found in the current dynamic scope,
    ///     the $recursiveRef is treated as "$ref": "#".
    return schema_reference_ResolveRef(joSchema, JsonString("#"));
}

/// -----------------------------------------------------------------------------------------------
///                                     KEYWORD VALIDATION
/// -----------------------------------------------------------------------------------------------

/// @todo
///     [x] Need SCHEMA_DRAFT_* constants defined.
///     [x] SCHEMA_SCOPE_SCHEMA is an array of $id, so how do we relate these?  Need to convert to
///         an int if it's an official draft, or leave as a string if it's a custom/user schema?
///         I mean, these functions are designed around teh json-schema.org drafts, so if we're not
///         using those, none of these are valid anyway?  So maybe add an int to match the constant
///         if it's a draft schema, or leave it as a string if it's custom.
///     [ ] Need handling methodology for the following keywords to support versioning:
///         [x] exclusiveMinimum (boolean in draft-4, number in draft-6+)
///         [x] exclusiveMaximum (boolean in draft-4, number in draft-6+)
///         [x] prefixItems (not supported in draft-4, -6, -7)
///         [x] items
///             - draft-4, -6, -7: schema or array of schemas. if a single schema, all members of array
///                 must validate against that schema. if an array of schema, tuple match.  extra members
///                 validated by additionalItems.
///             - draft-2019-09, -2020-12: schema applies to all members; use prefixItems to validate
///                 by tuple match.
///         [x] contains
///             - draft-4: not supported
///             - draft-6, -7, -2019-09, -2020-12: array must contain at least item that matches the schema
///         [x] minContains
///             - draft-4, -6, -7: not supported
///         [x] maxContains
///             - draft-4, -6, -7: not supported
///         [x] unevaluatedItems
///             - draft-4, -6, -7: not supported
///         [x] dependentRequired: not supported in draft-4, -6, -7
///         [x] dependentSchemas: not supported in draft-4, -6, -7
///         [x] propertyNames: not supported in draft-4
///         [x] unevaluatedProperties: not supported in draft-4, -6, -7
///         [x] if/then/else: not supported in draft-4, -6
///         [ ] $recursiveRef, $recursiveAnchor: only supported in draft-2019-09; deprecated in draft-2020-12
///         [ ] 'id' (superseded by '$id' in draft-6)
///         [ ] definitions (deprecated in draft-2020-12, replaced by '$defs')
///         [ ] dependencies (deprecated in draft-2020-12, replaced by 'dependent*')
///         [ ] I'm sure there's more. Frowny face.
///     [ ] How do we handle an nDraft = 0 (i.e. the current schema is a string, not a json-schema.org draft)?
///         if nDraft = 0, then it's not a draft schema, so we shouldn't be here anyway?

///     [ ] Need an "environment prep" fucntion that can be called by the entrant functions that will
///         [ ] set the current metaschema draft version
///         [ ] Schedule build variables for destruction

/// @brief Validates the global "type" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "type".
/// @returns An output object containing the validation result.
json schema_validate_Type(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    int nTypeType = JsonGetType(jSchema);
    if (nTypeType == JSON_TYPE_STRING)
    {
        int nInstanceType = JsonGetType(jInstance);

        if (JsonGetString(jSchema) == "number")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
                return schema_output_InsertChildAnnotation(joOutputUnit, "type", jSchema);
        }
        else if (JsonGetString(jSchema) == "integer")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
            {
                float f = JsonGetFloat(jInstance);

                if (IntToFloat(FloatToInt(f)) == f)
                    return schema_output_InsertChildAnnotation(joOutputUnit, "type", jSchema);
            }
        }
        else
        {
            json jaTypes = JsonParse(r"[
                ""null"",
                ""object"",
                ""array"",
                ""string"",
                ""integer"",
                ""float"",
                ""boolean""
            ]");

            json jiFind = JsonFind(jaTypes, jSchema);
            if (JsonGetType(jiFind) != JSON_TYPE_NULL && JsonGetInt(jiFind) == nInstanceType)
                return schema_output_InsertChildAnnotation(joOutputUnit, "type", jSchema);
        }
    }
    else if (nTypeType == JSON_TYPE_ARRAY || nTypeType == JSON_TYPE_OBJECT)
    {
        int i; for (; i < JsonGetLength(jSchema); i++)
        {
            json joValidate = schema_validate_Type(jInstance, JsonArrayGet(jSchema, i));
            if (schema_output_GetValid(joValidate))
                joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, joValidate);
        }
    }

    json jaAnnotations = JsonObjectGet(joOutputUnit, "annotations");
    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL || JsonGetLength(jaAnnotations) == 0)
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_type>"));
    else if (nTypeType == JSON_TYPE_ARRAY && JsonGetLength(jaAnnotations) > 0)
        return schema_output_InsertChildAnnotation(schema_output_GetOutputUnit(), "type", jSchema);

    return joOutputUnit;
}

/// @brief Validates the global "enum" and "const" keywords.
/// @param jInstance The instance to validate.
/// @param jSchema The array of valid elements for enum/const. Assumed to be validated against the metaschema.
/// @returns An output object containing the validation result.
/// @note Due to NWN's nlohmann::json implementation, JsonFind() conducts a
///     deep comparison of the instance and enum/const values; separate handling
///     for the various json types is not required.
json schema_validate_enum(json jInstance, json jSchema, string sDescriptor)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    if (JsonGetType(JsonFind(jSchema, jInstance)) == JSON_TYPE_NULL)
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_enum>") + sDescriptor);
    else
    {
        if (sDescriptor == "enum")
            return schema_output_InsertChildAnnotation(joOutputUnit, "enum", jSchema);
        else
            return schema_output_InsertChildAnnotation(joOutputUnit, "const", JsonArrayGet(jSchema, 0));
    }
}

/// @brief Validates the global "enum" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "enum".
/// @returns An output object containing the validation result.
json schema_validate_Enum(json jInstance, json jSchema)
{
    return schema_validate_enum(jInstance, jSchema, "enum");
}

/// @brief Validates the global "const" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "const".
/// @returns An output object containing the validation result.
json schema_validate_Const(json jInstance, json jSchema)
{
    return schema_validate_enum(jInstance, JsonArrayInsert(JsonArray(), jSchema), "const");
}

/// @brief Validates the string "minLength" keyword.
/// @param jsInstance The instance to validate.
/// @param jSchema The schema value for "minLength".
/// @returns An output object containing the validation result.
json schema_validate_MinLength(json jsInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note minLength is ignored for non-string instances.
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertChildAnnotation(joOutputUnit, "minLength", JsonString("keyword ignored due to instance type"));

    if (GetStringLength(JsonGetString(jsInstance)) * 1.0 >= JsonGetFloat(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, "minLength", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_minlength>"));
}

/// @brief Validates the string "maxLength" keyword.
/// @param jsInstance The instance to validate.
/// @param jSchema The schema value for "maxLength" (assumed to be a non-negative integer).
/// @returns An output object containing the validation result.
json schema_validate_MaxLength(json jsInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    
    /// @note maxLength is ignored for non-string instances.
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertChildAnnotation(joOutputUnit, "maxLength", JsonString("keyword ignored due to instance type"));

    if (GetStringLength(JsonGetString(jsInstance)) <= JsonGetInt(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, "maxLength", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_maxlength>"));
}

/// @brief Validates the string "pattern" keyword.
/// @param jsInstance The instance to validate.
/// @param jSchema The schema value for "pattern".
/// @returns An output object containing the validation result.
json schema_validate_Pattern(json jsInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    
    /// @note pattern is ignored for non-string instances.
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertChildAnnotation(joOutputUnit, "pattern", JsonString("keyword ignored due to instance type"));

    if (RegExpMatch(JsonGetString(jSchema), JsonGetString(jsInstance)) != JsonArray())
        return schema_output_InsertChildAnnotation(joOutputUnit, "pattern", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_pattern>"));
}

/// @todo
///     [ ] This whole function

/// @brief Validates the string "format" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "format".
/// @returns An output object containing the validation result.
json schema_validate_Format(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    if (JsonGetType(jInstance) != JSON_TYPE_STRING)
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<instance_string>"));

    string sInstance = JsonGetString(jInstance);
    string sFormat = JsonGetString(jSchema);
    int bValid = FALSE;

    if (sFormat == "email")    
    {
        bValid = RegExpMatch("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", sInstance) != JsonArray();
    }
    else if (sFormat == "hostname")
    {
        if (GetStringLength(sInstance) <= 253)
            bValid = RegExpMatch("^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", sInstance) != JsonArray();
    }
    else if (sFormat == "ipv4")
    {
        bValid = RegExpMatch("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", sInstance) != JsonArray();
    }
    else if (sFormat == "ipv6")
    {
        bValid = RegExpMatch("^([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}$", sInstance) != JsonArray()
              || RegExpMatch("^::([0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4}$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){1,7}:$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){1}(:[0-9A-Fa-f]{1,4}){1,6}$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){2}(:[0-9A-Fa-f]{1,4}){1,5}$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){3}(:[0-9A-Fa-f]{1,4}){1,4}$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){4}(:[0-9A-Fa-f]{1,4}){1,3}$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){5}(:[0-9A-Fa-f]{1,4}){1,2}$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}){1}$", sInstance) != JsonArray();
    }
    else if (sFormat == "uri")
    {
        bValid = RegExpMatch("^[a-zA-Z][a-zA-Z0-9+.-]*:[^\\s]*$", sInstance) != JsonArray();
    }
    else if (sFormat == "uri-reference")
    {
        bValid = (sInstance == "") || RegExpMatch("^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?$", sInstance) != JsonArray();
    }
    else if (sFormat == "iri")
    {
        bValid = RegExpMatch("^[\\w\\d\\-._~:/?#\\[\\]@!$&'()*+,;=%]+$", sInstance) != JsonArray();
    }
    else if (sFormat == "iri-reference")
    {
        bValid = (sInstance == "")
              || RegExpMatch("^[\\w\\d\\-._~:/?#\\[\\]@!$&'()*+,;=%]+$", sInstance) != JsonArray()
              || RegExpMatch("^[/?#]", sInstance) != JsonArray();
    }
    else if (sFormat == "date")
    {
        bValid = RegExpMatch("^\\d{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))$", sInstance) != JsonArray();
    }
    else if (sFormat == "date-time")
    {
        bValid = RegExpMatch("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$", sInstance) != JsonArray();
    }
    else if (sFormat == "time")
    {
        bValid = RegExpMatch("^\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})?$", sInstance) != JsonArray();
    }
    else if (sFormat == "duration")
    {
        bValid = RegExpMatch("^P(?!$)(\\d+Y)?(\\d+M)?(\\d+D)?(T(?!$)(\\d+H)?(\\d+M)?(\\d+(\\.\\d+)?S)?)?$", sInstance) != JsonArray();
    }
    else if (sFormat == "json-pointer")
    {
        bValid = (sInstance == "") || RegExpMatch("^(/([^/~]|~[01])*)*$", sInstance) != JsonArray();
    }
    else if (sFormat == "relative-json-pointer")
    {
        bValid = RegExpMatch("^(0|[1-9][0-9]*)(#|(/([^/~]|~[01])*)*)$", sInstance) != JsonArray();
    }
    else if (sFormat == "uuid")
    {
        bValid = RegExpMatch("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", sInstance) != JsonArray();
    }
    else if (sFormat == "regex")
    {
        bValid = (GetStringLength(sInstance) > 0);
        
        if (bValid)
        {
            bValid = RegExpMatch("^[^\\\\]*(\\\\.[^\\\\]*)*$", sInstance) != JsonArray();
        }
    }
    else
    {
        return schema_output_InsertChildError(joOutputUnit, "unsupported format: " + sFormat);
    }

    if (bValid)
        joOutputUnit = schema_output_InsertChildAnnotation(joOutputUnit, "format", jSchema);
    else
        return schema_output_InsertChildError(schema_output_SetValid(joOutputUnit, FALSE), "instance does not match format: " + sFormat);

    return joOutputUnit;
}

/// @todo
///     [ ] put all the array-returners together?

/// @brief Validates the number "minimum" and "exclusiveMinimum" keywords.
/// @param jInstance The instance to validate.
/// @param jMinimum The schema value for "minimum".
/// @param jExclusiveMinimum The schema value for "exclusiveMinimum".
/// @returns An output array containing the validation results(s).
json schema_validate_Minimum(json jInstance, json jMinimum, json jExclusiveMinimum)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaOutput = JsonArray();

    /// @note minimum and exclusiveMinimum are ignored for non-number instances.
    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "minimum", JsonString("keyword ignored due to instance type"));

    /// @note Validate minimum independently from exclusiveMinimum.
    int nMinimumType = JsonGetType(jMinimum);
    if (nMinimumType == JSON_TYPE_INTEGER || nMinimumType == JSON_TYPE_FLOAT)
    {
        if (JsonGetFloat(jInstance) >= JsonGetFloat(jMinimum))
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "minimum", jMinimum));
        else
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_minimum>")));
    }

    int nExclusiveMinimumType = JsonGetType(jExclusiveMinimum);
    if (nExclusiveMinimumType == JSON_TYPE_BOOL)
    {
        /// @note In early drafts, exclusiveMinimum is a boolean value and is dependent on minimum.  If
        ///     minimum is missing, exclusiveMinimum is ignored, otherwise, it is evaluated independently.
        if (nMinimumType == JSON_TYPE_INTEGER || nMinimumType == JSON_TYPE_FLOAT)
        {
            if (jExclusiveMinimum == JSON_TRUE && JsonGetFloat(jInstance) > JsonGetFloat(jMinimum) ||
                jExclusiveMinimum == JSON_FALSE && JsonGetFloat(jInstance) >= JsonGetFloat(jMinimum))
            {
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "exclusiveMinimum", jExclusiveMinimum));
            }
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_exclusiveminimum>")));
        }
    }
    else if (nExclusiveMinimumType == JSON_TYPE_INTEGER || nExclusiveMinimumType == JSON_TYPE_FLOAT)
    {
        /// @note In later drafts, exclusiveMinimum is a number and is validated independently of minimum.
        if (JsonGetFloat(jInstance) > JsonGetFloat(jExclusiveMinimum))
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "exclusiveMinimum", jExclusiveMinimum));
        else
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_exclusiveminimum>")));
    }

    return jaOutput;
}

/// @brief Validates the number "maximum" and "exclusiveMaximum" keywords.
/// @param jInstance The instance to validate.
/// @param jMaximum The schema value for "maximum".
/// @param jExclusiveMaximum The schema value for "exclusiveMaximum".
/// @returns An output array containing the validation results(s).
json schema_validate_Maximum(json jInstance, json jMaximum, json jExclusiveMaximum)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaOutput = JsonArray();

    /// @note maximum and exclusiveMaximum are ignored for non-number instances.
    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "maximum", JsonString("keyword ignored due to instance type"));

    /// @note Validate maximum independently from exclusiveMaximum.
    int nMaximumType = JsonGetType(jMaximum);
    if (nMaximumType == JSON_TYPE_INTEGER || nMaximumType == JSON_TYPE_FLOAT)
    {
        if (JsonGetFloat(jInstance) <= JsonGetFloat(jMaximum))
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "maximum", jMaximum));
        else
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_maximum>")));
    }

    int nExclusiveMaximumType = JsonGetType(jExclusiveMaximum);
    if (nExclusiveMaximumType == JSON_TYPE_BOOL)
    {
        /// @note In early drafts, exclusiveMaximum is a boolean value and is dependent on maximum.  If
        ///     maximum is missing, exclusiveMaximum is ignored, otherwise, it is evaluated independently.
        if (nMaximumType == JSON_TYPE_INTEGER || nMaximumType == JSON_TYPE_FLOAT)
        {
            if (jExclusiveMaximum == JSON_TRUE && JsonGetFloat(jInstance) < JsonGetFloat(jMaximum) ||
                jExclusiveMaximum == JSON_FALSE && JsonGetFloat(jInstance) <= JsonGetFloat(jMaximum))
            {
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "exclusiveMaximum", jExclusiveMaximum));
            }
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_exclusivemaximum>")));
        }
    }
    else if (nExclusiveMaximumType == JSON_TYPE_INTEGER || nExclusiveMaximumType == JSON_TYPE_FLOAT)
    {
        /// @note In later drafts, exclusiveMaximum is a number and is validated independently of maximum.
        if (JsonGetFloat(jInstance) < JsonGetFloat(jExclusiveMaximum))
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "exclusiveMaximum", jExclusiveMaximum));
        else
            jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_exclusivemaximum>")));
    }

    return jaOutput;
}

/// @private Validates the number "multipleOf" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "multipleOf".
/// @returns An output object containing the validation result.
json schema_validate_MultipleOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note multipleOf is ignored for non-number instances.
    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "multipleOf", JsonString("keyword ignored due to instance type"));

    float fMultiple = JsonGetFloat(jInstance) / JsonGetFloat(jSchema);
    if (fabs(fMultiple - IntToFloat(FloatToInt(fMultiple))) < 0.00001)
        return schema_output_InsertChildAnnotation(joOutputUnit, "multipleOf", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_multipleof>"));
}

/// @private Validates the array "minItems" keyword.
/// @param jaInstance The instance to validate.
/// @param jSchema The schema value for "minItems".
/// @returns An output object containing the validation result.
json schema_validate_MinItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note minItems is ignored for non-array instances.
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(joOutputUnit, "multipleOf", JsonString("keyword ignored due to instance type"));

    if (JsonGetLength(jaInstance) >= JsonGetInt(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, "minItems", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_minitems>"));
}

/// @private Validates the array "maxItems" keyword.
/// @param jaInstance The instance to validate.
/// @param jSchema The schema value for "maxItems".
/// @returns An output object containing the validation result.
json schema_validate_MaxItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note maxItems is ignored for non-array instances.
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(joOutputUnit, "multipleOf", JsonString("keyword ignored due to instance type"));

    if (JsonGetLength(jaInstance) <= JsonGetInt(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, "maxItems", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_maxitems>"));
}

/// @private Validates the array "uniqueItems" keyword.
/// @param jaInstance The instance to validate.
/// @param jSchema The schema value for "uniqueItems".
/// @returns An output object containing the validation result.
json schema_validate_UniqueItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note uniqueItems is ignored for non-array instances.
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(joOutputUnit, "uniqueItems", JsonString("keyword ignored due to instance type"));

    if (jSchema == JSON_FALSE)
        return schema_output_InsertChildAnnotation(joOutputUnit, "uniqueItems", jSchema);

    if (JsonGetLength(jaInstance) == JsonGetLength(JsonArrayTransform(jaInstance, JSON_ARRAY_UNIQUE)))
        return schema_output_InsertChildAnnotation(joOutputUnit, "uniqueItems", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_uniqueitems>"));
}

/// @todo
///     [ ] Change joItems to jItems since it can support old drafts that aren't objects?
///     [ ] Check error message/output unit return during testing.  This might not be the right message
///         All results of schema_core_Validate will be a full node, so this node object must be inserted
///         into the parent node for the evaluation?  How ill this output be structured? Maybe an array of
///         outputs that's parsed when returning to _validate?
///     [ ] Need another scope push/pop for the instance pathing; should be able to do the absolute pathing
///         automatically with the tracked nDraft data and the draft array.
///     [ ] JS "array" to Json array

/// @todo
///     [ ] Move this to reference section

/// @private Foundational documents allow javascript pseudo-arrays to be used in json and
///     treated as json arrays for validation purposes.  This function takes a valid json
///     object and checks if it appears to be a javascript pseudo-array.  If so, the
///     pseudo-array is converted to a valid json array.
/// @param jo Javascript pseudo-array.
/// @returns Json array containing the contents of the javascript pseudo-array.
json schema_reference_ObjectToArray(json jo)
{
    json jaKeys = JsonObjectKeys(jo);
    if (JsonFind(jaKeys, JsonString("length")) == JsonNull())
        return JsonNull();

    int nLength = JsonGetInt(JsonObjectGet(jo, "length"));
    if (nLength < 0)
        return JsonNull();

    if (JsonGetLength(jaKeys) != nLength + 1)
        return JsonNull();

    if (nLength == 0)
        return JsonArray();
    
    json ja = JsonArray();
    int i; for (; i < nLength; i++)
    {
        if (JsonFind(jaKeys, JsonString(IntToString(i))) == JsonNull())
            return JsonNull();

        ja = JsonArrayInsert(ja, JsonObjectGet(jo, IntToString(i)));
    }

    return ja;
}

/// @private Validates interdependent array keywords "prefixItems", "items", "contains",
///     "minContains", "maxContains", "unevaluatedItems".
/// @param jaInstance The array instance to validate.
/// @param jaPrefixItems The schema value for "prefixItems".
/// @param jItems The schema value for "items"
/// @param joContains The schema value for "contains".
/// @param jiMinContains The schema value for "minContains".
/// @param jiMaxContains The schema value for "maxContains".
/// @param jUnevaluatedItems The schema value for "unevaluatedItems".
/// @param jAdditionalItems The schema value for "additionalItems".
/// @returns An output object containing the validation result.
json schema_validate_Array(
    json jaInstance,
    json jaPrefixItems,
    json jItems,
    json joContains,
    json jiMinContains,
    json jiMaxContains,
    json jUnevaluatedItems,
    json jAdditionalItems
)
{
    json jaOutput = JsonArray();

    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(schema_output_GetOutputUnit(), "instance", JsonString("not evaluated"));

    int nInstanceLength = JsonGetLength(jaInstance);
    json jaEvaluatedIndices = JsonArray();

    /// @brief Validate prefixItems keyword.  In earlier drafts, this keyword didn't exist and the behavior was
    ///     modeled under the items keyword.  In later drafts, items must be an object or boolean.  If items is
    ///     an array and this validation is using an early draft, assume the items value is intended to model
    ///     the prefixItems behavior.

    /// @note The items keyword will cause some grief here.  If jItems is a json array, assume an early draft
    ///     and use jItems in place of jPrefixItems since the tuple validation process is identical.  If jItems
    ///     is a json object, determine if it is a pseudo-array.  If a pseudo-array, convert to a json array
    ///     and perform tuple validation.  Otherwise, validate prefixItems if it exists.

    json jSchemas;
    string sKeyword;

    if (JsonGetType(jItems) == JSON_TYPE_ARRAY)
    {
        jSchemas = jItems;
        sKeyword = "items";
    }
    else
    {
        jSchemas = jaPrefixItems;
        sKeyword = "prefixItems";
    }

    int nSchemasLength = JsonGetType(jSchemas) == JSON_TYPE_ARRAY ? JsonGetLength(jSchemas) : 0;
    if (nSchemasLength > 0)
    {
        json joParentOutputUnit = schema_output_GetOutputUnit();
       
        int i; for (; i < nSchemasLength && i < nInstanceLength; i++)
        {
            schema_scope_PushSchemaPath(IntToString(i));

            json joChildOutputUnit = schema_output_GetOutputUnit();

            json joTupleSchema = JsonArrayGet(jSchemas, i);
            json joResult = schema_core_Validate(JsonArrayGet(jaInstance, i), joTupleSchema);

            if (schema_output_GetValid(joResult))
                joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, sKeyword + "/" + IntToString(i), joTupleSchema);
            else
                /// @todo
                ///     [ ] move this error to the error aggregation function
                joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, "array item does not match " + sKeyword);

            jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonInt(i));

            if (schema_output_GetValid(joChildOutputUnit))
                joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
            else
                joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);

            schema_scope_PopSchemaPath();
        }

        jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    /// @brief Validate items keyword.  In later drafts, items can be a boolean (always/never matches) or a
    ///     schema against which to validate remaining unevaluated array members.  In earlier drafts, items was
    ///     a single schema to evaluate all array members against or an array of schema which behaves
    ///     functionally identical to prefixItems above.
    if (JsonGetType(jItems) == JSON_TYPE_BOOL)
    {
        json joChildOutputUnit, joParentOutputUnit = schema_output_GetOutputUnit();

        int i; for (i = nSchemasLength; i < nInstanceLength; i++)
        {
            schema_scope_PushSchemaPath(IntToString(i));
            jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonInt(i));

            if (jItems == JSON_TRUE)
                joChildOutputUnit = schema_output_InsertChildAnnotation(joParentOutputUnit, "items", JSON_TRUE);
            else if (jItems == JSON_FALSE)
                /// @todo
                ///      [ ] Move this error to the getter.
                joChildOutputUnit = schema_output_InsertChildError(joParentOutputUnit, "undefined items not allowed");

            if (schema_output_GetValid(joChildOutputUnit))
                joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
            else
                joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);

            schema_scope_PopSchemaPath();
        }

        jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }
    else if (JsonGetType(jItems) == JSON_TYPE_OBJECT)
    {
        /// @brief If items is a single schema, all remaining array members must to be evaluated against this
        ///     schema.  In earlier drafts, all array members will be evaluated against this schema since
        ///     prefixItems wasn't a valid keyword.
        json joParentOutputUnit = schema_output_GetOutputUnit();

        int i; for (i = nSchemasLength; i < nInstanceLength; i++)
        {
            schema_scope_PushSchemaPath(IntToString(i));

            json joChildOutputUnit = schema_output_GetOutputUnit();

            json jItem = JsonArrayGet(jaInstance, i);
            json jResult = schema_core_Validate(jItem, jItems);

            if (schema_output_GetValid(jResult))
                joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "items", jItems);
            else
                joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<validate_items>"));

            if (schema_output_GetValid(joChildOutputUnit))
                joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
            else
                joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);

            schema_scope_PopSchemaPath();
        }

        jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    /// @brief Validate contains, minContains, maxContains keywords.  minContains and maxContains are only
    ///     evaluated if contains keyword is present.
    if (JsonGetType(joContains) != JSON_TYPE_NULL)
    {
        json joOutputUnit = schema_output_GetOutputUnit();
        json jaContainsMatched = JsonArray();

        int nContainsType = JsonGetType(joContains);
        if (nContainsType == JSON_TYPE_OBJECT || nContainsType == JSON_TYPE_BOOL)
        {
            json joChildOutputUnit;

            int nMatches = 0;
            if (nContainsType == JSON_TYPE_BOOL)
            {
                /// @note if joContains is a boolean value, shortcut the validation process since the
                ///     result is known.
                if (joContains == JSON_TRUE)
                    nMatches = nInstanceLength;
                else if (joContains == JSON_FALSE)
                    nMatches = 0;
            }
            else
            {
                /// @note No shortcut available; this has to be done the hard way.  Validate each member
                ///     of the array against joContains, even if already validated against prefixItems
                ///     or items above.
                int i; for (; i < nInstanceLength; i++)
                {
                    json jItem = JsonArrayGet(jaInstance, i);
                    json jResult = schema_core_Validate(jItem, joContains);
                    if (schema_output_GetValid(jResult))
                    {
                        jaContainsMatched = JsonArrayInsert(jaContainsMatched, JsonInt(i));
                        nMatches++;
                    }
                }
            }

            if (nMatches > 0)
                joChildOutputUnit = schema_output_InsertChildAnnotation(joOutputUnit, "contains", joContains);
            else
                joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, "<validate_contains");

            jaOutput = JsonArrayInsert(jaOutput, joChildOutputUnit);

            int nMinContainsType = JsonGetType(jiMinContains);
            int nMaxContainsType = JsonGetType(jiMaxContains);

            if (nMinContainsType == JSON_TYPE_INTEGER || nMinContainsType == JSON_TYPE_FLOAT)
            {
                if (nMatches >= JsonGetInt(jiMinContains))
                    joChildOutputUnit = schema_output_InsertChildAnnotation(joOutputUnit, "minContains", jiMinContains);
                else
                    joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_mincontains>"));

                jaOutput = JsonArrayInsert(jaOutput, joChildOutputUnit);
            }

            if (nMaxContainsType == JSON_TYPE_INTEGER || nMaxContainsType == JSON_TYPE_FLOAT)
            {
                if (nMatches <= JsonGetInt(jiMaxContains))
                    joChildOutputUnit = schema_output_InsertChildAnnotation(joOutputUnit, "maxContains", jiMaxContains);
                else
                    joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_maxcontains>"));

                jaOutput = JsonArrayInsert(jaOutput, joChildOutputUnit);

            }

            if (nContainsType == JSON_TYPE_BOOL)
                return jaOutput;
            else
            {
                int i; for (; i < JsonGetLength(jaContainsMatched); i++)
                    jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonArrayGet(jaContainsMatched, i));
            }
        }
    }

    jaEvaluatedIndices = JsonArrayTransform(jaEvaluatedIndices, JSON_ARRAY_UNIQUE);
    
    int nAdditionalItemsType = JsonGetType(jAdditionalItems);
    int nUnevaluatedItemsType = JsonGetType(jUnevaluatedItems);

    if (nAdditionalItemsType == JSON_TYPE_OBJECT || nAdditionalItemsType == JSON_TYPE_BOOL)
    {
        sKeyword = "additionalItems";
        jSchemas = jAdditionalItems;
    }
    else if (nUnevaluatedItemsType == JSON_TYPE_OBJECT || nUnevaluatedItemsType == JSON_TYPE_BOOL)
    {
        sKeyword = "unevaluatedItems";
        jSchemas = jUnevaluatedItems;
    }

    /// @brief Validate unevaluatedItems and additionalItems keywords.  additionalItems is only evaluated if the items
    ///     keyword is an array; it is ignored if items is not present or if items is a schema.  unevaluatedItems should
    ///     be validated after all other keywords have been exhausted and unevaluated items remain in the array.
    int nSchemasType = JsonGetType(jSchemas);
    if (nSchemasType == JSON_TYPE_OBJECT || nSchemasType == JSON_TYPE_BOOL)
    {
        json joChildOutputUnit, joOutputUnit = schema_output_GetOutputUnit();

        if (nSchemasType == JSON_TYPE_BOOL)
        {
            if (jSchemas == JSON_TRUE)
                joChildOutputUnit = schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchemas);
            else if (jSchemas == JSON_FALSE)
                joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, "<validate_" + GetStringLowerCase(sKeyword) + ">");

            jaOutput = JsonArrayInsert(jaOutput, joChildOutputUnit);
        }
        else
        {
            json joParentOutputUnit = joOutputUnit;

            int i; for (; i < nInstanceLength; i++)
            {
                if (JsonFind(jaEvaluatedIndices, JsonInt(i)) == JsonNull())
                {
                    json jItem = JsonArrayGet(jaInstance, i);
                    json jResult = schema_core_Validate(jItem, jSchemas);

                    if (schema_output_GetValid(jResult))
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchemas);
                    else
                        joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, "<validate_" + GetStringLowerCase(sKeyword) + ">");

                    if (schema_output_GetValid(joChildOutputUnit))
                        joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                    else
                        joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);
                }
            }

            jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
        }
    }

    return jaOutput;
}

/// @private Validates the object "required" keyword.
/// @param joInstance The object instance to validate.
/// @param jSchema The schema value for "required".
/// @returns An output object containing the validation result.
json schema_validate_Required(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note required is ignored for non-object instances.
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "required", JsonString("keyword ignored due to instance type"));

    json jaMissingProperties = JsonArray();
    json jaInstanceKeys = JsonObjectKeys(joInstance);
    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        json jProperty = JsonArrayGet(jSchema, i);
        if (JsonFind(jaInstanceKeys, jProperty) == JsonNull())
            jaMissingProperties = JsonArrayInsert(jaMissingProperties, jProperty);
    }

    if (JsonGetLength(jaMissingProperties) > 0)
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_required>"));
    else
        return schema_output_InsertChildAnnotation(joOutputUnit, "required", jSchema);
}

/// @private Validates the object "minProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jSchema The schema value for "minProperties".
/// @returns An output object containing the validation result.
json schema_validate_MinProperties(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    
    /// @note minProperties is ignored for non-object instances.
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "minProperties", JsonString("keyword ignored due to instance type"));
    
    if (JsonGetLength(joInstance) < JsonGetInt(jSchema))
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_minproperties>"));
    else
        return schema_output_InsertChildAnnotation(joOutputUnit, "minProperties", jSchema);
}

/// @private Validates the object "maxProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jSchema The schema value for "maxProperties".
/// @returns An output object containing the validation result.
json schema_validate_MaxProperties(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note maxProperties is ignored for non-object instances.
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "maxProperties", JsonString("keyword ignored due to instance type"));

    if (JsonGetLength(joInstance) > JsonGetInt(jSchema))
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_maxproperties>"));
    else
        return schema_output_InsertChildAnnotation(joOutputUnit, "maxProperties", jSchema);
}

/// @brief Validates the object "dependentRequired" keyword.
/// @param joInstance The object instance to validate.
/// @param joDependentRequired The schema value for "dependentRequired".
/// @returns An output object containing the validation result.
json schema_validate_DependentRequired(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @note dependentRequired is ignored for non-object instances.    
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "dependentRequired", JsonString("keyword ignored due to instance type"));

    json jaInstanceKeys = JsonObjectKeys(joInstance);
    json jaDependentRequiredKeys = JsonObjectKeys(jSchema);

    json joParentOutputUnit = joOutputUnit;

    int i; for (; i < JsonGetLength(jaDependentRequiredKeys); i++)
    {
        string sDependentRequiredKey = JsonGetString(JsonArrayGet(jaDependentRequiredKeys, i));
        if (JsonFind(jaInstanceKeys, JsonString(sDependentRequiredKey)) != JsonNull())
        {
            json jaRequiredKeys = JsonObjectGet(jSchema, sDependentRequiredKey);
            if (JsonGetType(jaRequiredKeys) == JSON_TYPE_ARRAY)
            {
                int j; for (; j < JsonGetLength(jaRequiredKeys); j++)
                {
                    if (JsonFind(jaInstanceKeys, JsonArrayGet(jaRequiredKeys, j)) == JsonNull())
                    {
                        json joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_dependentrequired>"));
                        joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                    }
                }
            }
        }
    }

    json jaErrors = JsonObjectGet(joParentOutputUnit, "errors");
    if (JsonGetType(jaErrors) == JSON_TYPE_NULL || JsonGetLength(jaErrors) == 0)
        return schema_output_InsertChildAnnotation(joOutputUnit, "dependentRequired", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_dependentrequired>"));
}

/// @brief Validates interdependent object keywords "properties", "patternProperties",
///     "additionalProperties", "dependentSchemas", "propertyNames", "unevaluatedProperties".
/// @param joInstance The object instance to validate.
/// @param joProperties The schema value for "properties".
/// @param joPatternProperties The schema value for "patternProperties".
/// @param jAdditionalProperties The schema value for "additionalProperties".
/// @param joDependencies The schema value for "dependencies".
/// @param joDependentSchemas The schema value for "dependentSchemas".
/// @param jPropertyNames The schema value for "propertyNames".
/// @param jUnevaluatedProperties The schema value for "unevaluatedProperties".
/// @returns An output object containing the validation result.
json schema_validate_Object(
    json joInstance,
    json joProperties,
    json joPatternProperties,
    json jAdditionalProperties,
    json joDependencies,
    json joDependentSchemas,
    json jPropertyNames,
    json jUnevaluatedProperties
)
{
    json jaOutput = JsonArray();
    json joOutputUnit = schema_output_GetOutputUnit();

    /// @todo
    ///     [ ] This error sucks, because most of the validators below won't work if instance is not an object
    ///         and "properties" may not have even been passed, which could lead to confusion in the output.

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, "properties", JsonString("keyword ignored due to instance type"));

    json jaEvaluatedProperties = JsonArray();
    json jaInstanceKeys = JsonObjectKeys(joInstance);
    int nInstanceKeys = JsonGetLength(jaInstanceKeys);

    /// @brief Evaluate properties keyword.
    if (JsonGetType(joProperties) == JSON_TYPE_OBJECT)
    {
        json jaPropertyKeys = JsonObjectKeys(joProperties);
        json joParentOutputUnit = joOutputUnit;

        int i; for (; i < nInstanceKeys; i++)
        {
            string sPropertyKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(jaPropertyKeys, JsonString(sPropertyKey)) != JsonNull())
            {
                json joChildOutputUnit = joOutputUnit;
               
                json joProperty = JsonObjectGet(joProperties, sPropertyKey);
                json joResult = schema_core_Validate(JsonObjectGet(joInstance, sPropertyKey), joProperty);
                
                if (schema_output_GetValid(joResult))
                    joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "properties", joProperty);
                else
                    joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<validate_properties>"));

                jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sPropertyKey));

                if (schema_output_GetValid(joChildOutputUnit))
                    joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                else
                    joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);
            }
        }

        jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    // 2. patternProperties
    if (JsonGetType(joPatternProperties) == JSON_TYPE_OBJECT)
    {
        json jaPatternKeys = JsonObjectKeys(joPatternProperties);
        json joParentOutputUnit = joOutputUnit;
        int nPatternKeys = JsonGetLength(jaPatternKeys);
        
        int i; for (; i < nInstanceKeys; i++)
        {
            string sKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            int j; for (; j < nPatternKeys; ++j)
            {
                json joChildOutputUnit = joOutputUnit;

                string sPattern = JsonGetString(JsonArrayGet(jaPatternKeys, j));
                json jaMatch = RegExpMatch(sPattern, sKey);
                if (JsonGetType(jaMatch) != JSON_TYPE_NULL && jaMatch != JsonArray())
                {
                    json joPatternSchema = JsonObjectGet(joPatternProperties, sPattern);
                    json joResult = schema_core_Validate(JsonObjectGet(joInstance, sKey), joPatternSchema);
                    
                    if (schema_output_GetValid(joResult))
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "patternProperties", joPatternSchema);
                    else
                        joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<validate_patternproperties>"));

                    jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sKey));

                    if (schema_output_GetValid(joChildOutputUnit))
                        joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                    else
                        joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);
                }
            }
        }
        
        if (JsonGetLength(JsonObjectGet(joParentOutputUnit, "annotations")) > 0 || JsonGetLength(JsonObjectGet(joParentOutputUnit, "errors")) > 0)
            jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    // 3. additionalProperties
    // Only applies to properties not matched by properties or patternProperties
    int nAdditionalPropertiesType = JsonGetType(jAdditionalProperties);
    if (nAdditionalPropertiesType == JSON_TYPE_OBJECT || nAdditionalPropertiesType == JSON_TYPE_BOOL)
    {
        json joParentOutputUnit = joOutputUnit;

        int i; for (; i < nInstanceKeys; ++i)
        {
            json joChildOutputUnit = joOutputUnit;

            string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(jaEvaluatedProperties, JsonString(sInstanceKey)) == JsonNull())
            {
                if (nAdditionalPropertiesType == JSON_TYPE_BOOL)
                {
                    if (jAdditionalProperties == JSON_TRUE)
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "additionalProperties", jAdditionalProperties);
                    else
                        joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<additionalProperties>"));
                }
                else if (nAdditionalPropertiesType == JSON_TYPE_OBJECT)
                {
                    json joResult = schema_core_Validate(JsonObjectGet(joInstance, sInstanceKey), jAdditionalProperties);
                    if (schema_output_GetValid(joResult))
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "additionalProperties", jAdditionalProperties);
                    else
                        joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<additionalProperties>"));
                }

                jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sInstanceKey));
            }
        }
        
        jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    // 5. propertyNames
    int nPropertyNamesType = JsonGetType(jPropertyNames);
    if (nPropertyNamesType == JSON_TYPE_OBJECT || nPropertyNamesType == JSON_TYPE_BOOL)
    {
        json joParentOutputUnit = joOutputUnit;

        if (nPropertyNamesType == JSON_TYPE_BOOL)
        {
            if (jPropertyNames == JSON_FALSE)
            {
                if (nInstanceKeys == 0)
                    joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, schema_output_InsertChildAnnotation(joOutputUnit, "propertyNames", jPropertyNames));
                else if (nInstanceKeys > 0)
                    joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_propertynames>")));
            }
        }
        else if (nPropertyNamesType == JSON_TYPE_OBJECT)
        {
            if (nInstanceKeys == 0)
                joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, schema_output_InsertChildAnnotation(joOutputUnit, "propertyNames", jPropertyNames));
            else
            {
                int i; for (; i < nInstanceKeys; i++)
                {
                    json joChildOutputUnit = joOutputUnit;

                    string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                    json joResult = schema_core_Validate(JsonString(sInstanceKey), jPropertyNames);

                    if (schema_output_GetValid(joResult))
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "propertyNames", jPropertyNames);
                    else
                        joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<validate_propertynames>"));

                    if (schema_output_GetValid(joChildOutputUnit))
                        joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                    else
                        joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);
                }
            }
        }

        if (JsonGetLength(JsonObjectGet(joParentOutputUnit, "annotations")) > 0 || JsonGetLength(JsonObjectGet(joParentOutputUnit, "errors")) > 0)
            jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    // 5.5 dependencies
    ///     [ ] Check for pseudo-arrays here
    ///     [ ] check for pseudo-arrays in `examples`

    ///     [ ] HUUUUUUUUUGE dependencies is just a new name for dependentRequired and dependentSchemas, but split
    //          if dependencies is an array, then call dependedRequired,
    ///         if dependencies is object/boolean, call dependentScehams and track evaluated properties.

    /// @todo
    ///     [ ] if hyper-schema is included, check for pseudo-arrays in patternRequired.

    /// @todo
    ///     [ ] Apparently this needs to have collected evaluated properties from the schema_core_validate function.  Figure out how to
    ///         recursively collect this.  All of these have to be added to jaEvaluatedProperties
    ///     [ ] Use an sql query to tap into the names of evaluated properties from the validation result, then add the all in here, but
    ///         can't do this until I've built out the entire output network and it properly populate so I nkow what I need to find within
    ///         the query.
    ///     [ ] Seems a couple of these can be independent. make it so.

    /*
        SELECT
            substr(jt2.value, 3) as property_name,  -- extract 'foo' from '#/foo'
            jt1.value as keyword_location
        FROM
            validation_results,
            json_tree(validation_results.output) as jt1
            JOIN json_tree(validation_results.output, jt1.path) as jt2
        WHERE
            jt2.key = 'instanceLocation'
            AND jt2.value LIKE '#/%'
            AND jt1.key = 'keywordLocation'
            AND (
                jt1.value LIKE '%/properties/%'
                OR jt1.value LIKE '%/patternProperties/%'
                OR jt1.value LIKE '%/additionalProperties'
                OR jt1.value LIKE '%/dependentSchemas/%'
                OR jt1.value LIKE '%/propertyNames'
        )
    */

    ///     [ ] This is a right mess, clean it up!  Probably the biggest project remaining here.
    ///     [ ] Need to track evaluated properties


    // 4. dependentSchemas
    /// @todo
    ///     [ ] this requires a deep dive to obtain evaluated properties, apparently, see the mess above.
    ///     [ ] need to handle boolean
    if (JsonGetType(joDependentSchemas) == JSON_TYPE_OBJECT)
    {
        json joParentOutputUnit = joOutputUnit;

        json jaDependentKeys = JsonObjectKeys(joDependentSchemas);
        int nDependentKeys = JsonGetLength(jaDependentKeys);
        
        int i; for (; i < nDependentKeys; i++)
        {
            json joChildOutputUnit = joOutputUnit;

            string sDependentKey = JsonGetString(JsonArrayGet(jaDependentKeys, i));
            if (JsonFind(jaInstanceKeys, JsonString(sDependentKey)) != JsonNull())
            {
                json joDependentSchema = JsonObjectGet(joDependentSchemas, sDependentKey);
                json joResult = schema_core_Validate(joInstance, joDependentSchema);
                
                if (schema_output_GetValid(joResult))
                    joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "dependentSchemas", joDependentSchema);
                else
                    joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<validate_dependentschemas>"));
            
                if (schema_output_GetValid(joChildOutputUnit))
                    joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                else
                    joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);

                jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sDependentKey));
            }
        }

        jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    /// @brief Validate all remaining unevaluated properties.
    int nUnevaluatedPropertiesType = JsonGetType(jUnevaluatedProperties);
    if (nUnevaluatedPropertiesType == JSON_TYPE_OBJECT || nUnevaluatedPropertiesType == JSON_TYPE_BOOL)
    {
        json joParentOutputUnit = joOutputUnit;
        
        int i; for (; i < nInstanceKeys; ++i)
        {
            json joChildOutputUnit = joOutputUnit;

            string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(jaEvaluatedProperties, JsonString(sInstanceKey)) == JsonNull())
            {
                if (nUnevaluatedPropertiesType == JSON_TYPE_BOOL)
                {
                    if (jUnevaluatedProperties == JSON_TRUE)
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "unevaluatedProperties", jUnevaluatedProperties);
                    else
                        joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("validate_unevaluatedproperties"));
                }
                else if (nUnevaluatedPropertiesType == JSON_TYPE_OBJECT)
                {
                    json joResult = schema_core_Validate(JsonObjectGet(joInstance, sInstanceKey), jUnevaluatedProperties);
                    
                    if (schema_output_GetValid(joResult))
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "unevaluatedProperties", jUnevaluatedProperties);
                    else
                        joOutputUnit = schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("validate_unevaluatedproperties"));

                    if (schema_output_GetValid(joChildOutputUnit))
                        joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                    else
                        joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);
                }
            }
        }

        jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    return jaOutput;
}

/// @brief Validates the applicator "not" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "not".
/// @returns An output object containing the validation result.
json schema_validate_Not(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    if (schema_output_GetValid(schema_core_Validate(jInstance, jSchema)))
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_not>"));
    else
        return schema_output_InsertChildAnnotation(joOutputUnit, "not", jSchema);
}

/// @todo
///     [ ] See where push/pop lexical are required throughout all of the functions that call schema_core_validate()
///     [ ] change the variable argument to the same for all to make copy/paste easier!

/// @brief Validates the applicator "allOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "allOf".
/// @returns An output object containing the validation result.
json schema_validate_AllOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json joParentOutputUnit = joOutputUnit;

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        if (!schema_output_GetValid(schema_core_Validate(jInstance, JsonArrayGet(jSchema, i))))
        {
            json joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_allof>"));
            joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);
        }

        schema_scope_PopSchemaPath();
    }

    json jaErrors = JsonObjectGet(joParentOutputUnit, "errors");
    if (JsonGetType(jaErrors) == JSON_TYPE_NULL || JsonGetLength(jaErrors) == 0)
        return schema_output_InsertChildAnnotation(joOutputUnit, "allOf", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_allof>"));
}

/// @brief Validates the applicator "anyOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "anyOf".
/// @returns An output object containing the validation result.
json schema_validate_AnyOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        if (schema_output_GetValid(schema_core_Validate(jInstance, JsonArrayGet(jSchema, i))))
        {
            schema_scope_PopSchemaPath();
            return schema_output_InsertChildAnnotation(joOutputUnit, "anyOf", jSchema);
        }

        schema_scope_PopSchemaPath();
    }

    return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_anyof>"));
}

/// @brief Validates the applicator "oneOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "oneOf".
/// @returns An output object containing the validation result.
json schema_validate_OneOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    int nMatches;
    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        if (schema_output_GetValid(schema_core_Validate(jInstance, JsonArrayGet(jSchema, i))))
            nMatches++;

        schema_scope_PopSchemaPath();
    }

    if (nMatches == 1)
        return schema_output_InsertChildAnnotation(joOutputUnit, "oneOf", jSchema);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_oneof>"));
}

/// @brief Validates interdependent applicator keywords "if", "then", "else".
/// @param joInstance The object instance to validate.
/// @param joIf The schema value for "if".
/// @param joThen The schema value for "then".
/// @param joElse The schema value for "else".
/// @returns An output object containing the validation result.
json schema_validate_If(json jInstance, json joIf, json joThen, json joElse)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaOutput = JsonArray();

    jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "if", joIf));

    if (schema_output_GetValid(schema_core_Validate(jInstance, joIf)))
    {
        if (JsonGetType(joThen) != JSON_TYPE_NULL)
        {
            if (schema_output_GetValid(schema_core_Validate(jInstance, joThen)))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "then", joThen));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_then>")));
        }
    }
    else
    {
        if (JsonGetType(joElse) != JSON_TYPE_NULL)
        {
            if (schema_output_GetValid(schema_core_Validate(jInstance, joElse)))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, "else", joElse));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_else>")));
        }
    }

    return jaOutput;
}

/// @brief Annotates the output with a metadata keyword.
/// @param sKey The metadata keyword.
/// @param jValue The value for the metadata keyword.
/// @returns An output object containing the annotation.
json schema_validate_Metadata(string sKey, json jValue)
{
    return schema_output_InsertChildAnnotation(schema_output_GetOutputUnit(), sKey, jValue);
}

json schema_core_Validate(json jInstance, json joSchema)
{
    /// @todo
    ///     [ ] joSchema could potentially be JsonNull(), handle that!

    json jResult = JsonNull();
    json joOutputUnit = schema_output_GetOutputUnit();

    if (joSchema == JSON_TRUE || joSchema == JsonObject())
        return schema_output_SetValid(joOutputUnit, TRUE);
    if (joSchema == JSON_FALSE)
        return schema_output_SetValid(joOutputUnit, FALSE);

    json jaSchemaKeys = JsonObjectKeys(joSchema);
    
    /// @brief Keep track of the current schema.  $schema should only be present in the root note
    ///     of any schema, so if it's present, assume that we're starting a new validation.
    string sSchema = JsonGetString(JsonObjectGet(joSchema, "$schema"));
    if (sSchema != "")
        schema_scope_PushSchema(sSchema);

    /// @ todo
    ///     [ ] Handle nDraft = 0 ?
    ///     [ ] can this be done without nDraft at all?
    int nDraft = JsonGetInt(schema_scope_GetSchema());

    int bDynamicAnchor = FALSE;
    if (JsonFind(jaSchemaKeys, JsonString("$dynamicAnchor")) != JsonNull() ||
        JsonFind(jaSchemaKeys, JsonString("$recursiveAnchor")) != JsonNull())
    {
        schema_scope_PushDynamic(joSchema);
        bDynamicAnchor = TRUE;
    }

    /// @todo
    ///     [ ] These resolution functions can and will return JsonNull().  Check for that before
    ///         invoking another validation process.
    ///     [ ] Need ~1 and ~0 unescaping methodology.  See RFC
    
    /// @brief Resolve references, dynamic references and recursive references.  Dynamic and recursive
    ///     references take advantage of dynamic scope to find the appropriate anchor/subschema.  If
    ///     dynamic or recursive references cannot be resolved for any reason, they revert to resolving
    ///     exactly like a normal $ref.
    json jRef = JsonObjectGet(joSchema, "$ref");
    if (JsonGetType(jRef) != JSON_TYPE_NULL)
    {
        schema_scope_PushSchemaPath("$ref");
        jResult = schema_core_Validate(jInstance, schema_reference_ResolveRef(joSchema, jRef));
        schema_scope_PopSchemaPath();
    }
    else
    {
        jRef = JsonObjectGet(joSchema, "$dynamicRef");
        if (JsonGetType(jRef) != JSON_TYPE_NULL)
        {
            schema_scope_PushSchemaPath("$dynamicRef");
            jResult = schema_core_Validate(jInstance, schema_reference_ResolveDynamicRef(joSchema, jRef));
            schema_scope_PopSchemaPath();
        }
        else
        {
            jRef = JsonObjectGet(joSchema, "$recursiveRef");
            if (JsonGetType(jRef) != JSON_TYPE_NULL)
            {
                schema_scope_PushSchemaPath("$recursiveRef");
                jResult = schema_core_Validate(jInstance, schema_reference_ResolveRecursiveRef(joSchema));
                schema_scope_PopSchemaPath();
            }
        }
    }

    /// @brief If a reference was found, incorporate the results into the output unit.  For schema drafts-4,
    /// -6 and -7, the foundational documents forbid processing adjacent keywords.

    /// @todo
    ///     [ ] Find a way to do this without nDraft; maybe the json array of schema ids?
    ///         unlikely, since this is called from everything and joSchema may not always be the base schema
    if (JsonGetType(jRef) != JSON_TYPE_NULL)
    {
        if (JsonGetType(jResult) != JSON_TYPE_NULL)
        {
            if (schema_output_GetValid(jResult))
                joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, jResult);
            else
                joOutputUnit = schema_output_InsertParentError(joOutputUnit, jResult);
        }
        else
        {
            /// @todo
            ///     [ ] What do we do with a JsonNull() return from $ref validation?
        }

        if (nDraft >= SCHEMA_DRAFT_4 && nDraft <= SCHEMA_DRAFT_7)
        {
            if (bDynamicAnchor)
                schema_scope_PopDynamic();

            return joOutputUnit;
        }
    }

    int HANDLED_CONDITIONAL = 0x01;
    int HANDLED_ARRAY = 0x02;
    int HANDLED_OBJECT = 0x04;
    int HANDLED_MINIMUM = 0x08;
    int HANDLED_MAXIMUM = 0x10;
    int nHandledFlags;

    int i; for (; i < JsonGetLength(jaSchemaKeys); i++)
    {
        string sKey = JsonGetString(JsonArrayGet(jaSchemaKeys, i));
        schema_scope_PushSchemaPath(sKey);
        
        if (sKey == "if" || sKey == "then" || sKey == "else")
        {
            if (!(nHandledFlags & HANDLED_CONDITIONAL))
            {
                jResult = schema_validate_If(jInstance,
                    JsonObjectGet(joSchema, "if"),
                    JsonObjectGet(joSchema, "then"),
                    JsonObjectGet(joSchema, "else")
                );
                nHandledFlags |= HANDLED_CONDITIONAL;
            }
        }
        else if (sKey == "prefixItems" || sKey == "items" || sKey == "contains" ||
            sKey == "minContains" || sKey == "maxContains" || sKey == "unevaluatedItems" ||
            sKey == "additionalItems")
        {
            if (!(nHandledFlags & HANDLED_ARRAY))
            {
                jResult = schema_validate_Array(jInstance,
                    JsonObjectGet(joSchema, "prefixItems"),
                    JsonObjectGet(joSchema, "items"),
                    JsonObjectGet(joSchema, "contains"),
                    JsonObjectGet(joSchema, "minContains"),
                    JsonObjectGet(joSchema, "maxContains"),
                    JsonObjectGet(joSchema, "unevaluatedItems"),
                    JsonObjectGet(joSchema, "additionalItems")
                );
                nHandledFlags |= HANDLED_ARRAY;
            }
        }
        else if (sKey == "properties" || sKey == "patternProperties" ||
            sKey == "additionalProperties" || sKey == "dependentSchemas" ||
            sKey == "propertyNames" || sKey == "unevaluatedProperties")
        {
            if (!(nHandledFlags & HANDLED_OBJECT))
            {
                jResult = schema_validate_Object(jInstance,
                    JsonObjectGet(joSchema, "properties"),
                    JsonObjectGet(joSchema, "patternProperties"),
                    JsonObjectGet(joSchema, "additionalProperties"),
                    JsonObjectGet(joSchema, "dependencies"),
                    JsonObjectGet(joSchema, "dependentSchemas"),
                    JsonObjectGet(joSchema, "propertyNames"),
                    JsonObjectGet(joSchema, "unevaluatedProperties")
                );
                nHandledFlags |= HANDLED_OBJECT;
            }
            else
                continue;
        }
        else if (sKey == "minimum" || sKey == "exclusiveMinimum")
        {
            if (!(nHandledFlags & HANDLED_MINIMUM))
            {
                jResult = schema_validate_Minimum(jInstance,
                    JsonObjectGet(joSchema, "minimum"),
                    JsonObjectGet(joSchema, "exclusiveMinimum"));
                nHandledFlags |= HANDLED_MINIMUM;
            }
        }
        else if (sKey == "maximum" || sKey == "exclusiveMaximum")
        {
            if (!(nHandledFlags & HANDLED_MAXIMUM))
            {
                jResult = schema_validate_Maximum(jInstance,
                    JsonObjectGet(joSchema, "maximum"),
                    JsonObjectGet(joSchema, "exclusiveMaximum"));
                nHandledFlags |= HANDLED_MAXIMUM;
            }
        }
        else if (sKey == "title" || sKey == "description" || sKey == "default" ||
            sKey == "deprecated" || sKey == "readOnly" || sKey == "writeOnly" ||
            sKey == "examples")
        {
            jResult = schema_validate_Metadata(sKey, JsonObjectGet(joSchema, sKey));
        }
        else if (sKey == "allOf")            {jResult = schema_validate_AllOf(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "anyOf")            {jResult = schema_validate_AnyOf(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "oneOf")            {jResult = schema_validate_OneOf(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "not")              {jResult = schema_validate_Not(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "required")         {jResult = schema_validate_Required(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "minProperties")    {jResult = schema_validate_MinProperties(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "maxProperties")    {jResult = schema_validate_MaxProperties(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "dependentRequired"){jResult = schema_validate_DependentRequired(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "type")             {jResult = schema_validate_Type(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "enum")             {jResult = schema_validate_Enum(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "const")            {jResult = schema_validate_Const(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "multipleOf")       {jResult = schema_validate_MultipleOf(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "maxLength")        {jResult = schema_validate_MaxLength(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "minLength")        {jResult = schema_validate_MinLength(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "pattern")          {jResult = schema_validate_Pattern(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "maxItems")         {jResult = schema_validate_MaxItems(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "minItems")         {jResult = schema_validate_MinItems(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "uniqueItems")      {jResult = schema_validate_UniqueItems(jInstance, JsonObjectGet(joSchema, sKey));}
        else if (sKey == "format")           {jResult = schema_validate_Format(jInstance, JsonObjectGet(joSchema, sKey));}

        int nResultType = JsonGetType(jResult);
        if (nResultType == JSON_TYPE_ARRAY)
        {
            int i; for (; i < JsonGetLength(jResult); i++)
            {
                json joResult = JsonArrayGet(jResult, i);
                if (schema_output_GetValid(joResult))
                    joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, joResult);
                else
                    joOutputUnit = schema_output_InsertParentError(joOutputUnit, joResult);
            }
        }
        else if (nResultType == JSON_TYPE_OBJECT)
        {
            if (schema_output_GetValid(jResult))
                joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, jResult);
            else
                joOutputUnit = schema_output_InsertParentError(joOutputUnit, jResult);
        }
        else
        {
            jResult = JsonObjectSet(JsonObject(), "valid", JsonBool(TRUE));
            /// @todo
            ///     [ ] When integrating joResult, we'll make JsonNull() mean that the keyword is not handled and/or supported?
        }

        schema_scope_PopSchemaPath();        
    }

    if (bDynamicAnchor)
        schema_scope_PopDynamic();

    return jResult;
}

json schema_core_GetValidationResult()
{
    return GetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT");
}

/// @todo
///     [ ] Create public-access function and prototypes.
///         [ ] Validate and save schema without validating instance
///         [ ] Retrieve a schema
///         [ ] Delete a schema
///         [ ] Validate an instance against a specified saved schema
///         [ ]
///         [ ] Validate an instance against an adhoc schema
///         [ ] List all schema
///     [ ] Create schema_core_PrepareEnvironment() for first run.
///     [ ] If $schema is not included in the schema, we assume latest
///         draft, but can we allow the user to specify a draft, as a weird
///         test-case backup backup?

// Registers (validates and saves) a schema (joSchema).
// If a schema with the same $id exists, it is overwritten.
int RegisterSchema(json joSchema) {
    // TODO: Validate joSchema against metaschema
    // TODO: Save joSchema to database (overwrite if $id exists)
    return 0; // stub
}

// Validates a schema (joSchema) against the metaschema.
// Does NOT save the schema.
int ValidateSchema(json joSchema) {
    // TODO: Validate joSchema against metaschema
    return 0; // stub
}

// Retrieves a schema (joSchema) by sID.
json GetSchema(string sID) {
    // TODO: Query and return joSchema from database by sID
    json joSchema; // stub: replace with actual retrieval
    return joSchema;
}

// Deletes a schema (joSchema) by sID.
int DeleteSchema(string sID) {
    // TODO: Remove joSchema from database by sID
    return 0; // stub
}

// Lists all registered schema IDs.
// Returns a JSON string (array or object) containing all schema IDs.
string ListSchemas() {
    // TODO: Query and return all schema IDs as a JSON string
    return ""; // stub
}

// Validates an instance (jInstance) against a pre-registered schema (by sID).
int ValidateInstance(json jInstance, string sID) {
    // TODO: Retrieve joSchema by sID
    // TODO: Validate jInstance using schema_core_Validate
    return 0; // stub
}

// Validates an instance (jInstance) against a provided schema (joSchema, ad-hoc).
// Optionally registers the schema if it has a $id.
int ValidateInstanceAdHoc(json jInstance, json joSchema) {
    // TODO: Validate joSchema against metaschema
    // TODO: If $id is present, optionally register
    // TODO: Validate jInstance using schema_core_Validate
    
    schema_scope_Destroy();
    schema_core_Validate(jInstance, joSchema);

    //Debug(HexColorString("Validation Result:", COLOR_ORANGE_LIGHT));
    //Debug(HexColorString(JsonDump(schema_core_GetValidationResult(), 4), COLOR_BLUE_LIGHT));

    return schema_output_GetValid(schema_core_GetValidationResult());
}

/*
    entry points need to:
    - schedule the variable destruction
    - call for schema validation
    - save the schema is valid and an id exists
*/
