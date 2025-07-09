
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
///     [ ] debugging stuff, remove if able, or make prettier
int SOURCE=TRUE;

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
    ""SCHEMA_SCOPE_SCHEMAPATH"": [],
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

void schema_output_SaveValidationResult(json joResult)
{
    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joResult);
}

json schema_output_GetValidationResult()
{
    return GetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT");
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
    DelayCommand(0.01, DeleteLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT"));
    DelayCommand(0.01, DeleteLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH"));

    json jaScopes = JsonObjectKeys(joScopes);
    int i; for (; i < JsonGetLength(jaScopes); i++)
        DelayCommand(0.01, DeleteLocalJson(GetModule(), JsonGetString(JsonArrayGet(jaScopes, i))));
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

void schema_scope_ReplaceSchemaPath(string sPath)
{
    schema_scope_PopSchemaPath();
    schema_scope_PushSchemaPath(sPath);
}

void schema_scope_ReplaceInstancePath(string sPath)
{
    schema_scope_PopInstancePath();
    schema_scope_PushInstancePath(sPath);
}

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
    if (GetStringLeft(sError, 1) != "<")
        sError = "<validate_" + sError + ">";

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
json schema_output_GetOutputUnit(string sSource = "")
{
    /// @todo
    ///     [ ] sSource is a temproary debugging measure, remove!

    json joOutputUnit = schema_output_GetMinimalObject();
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);
    joOutputUnit = schema_output_SetValid(joOutputUnit, TRUE);

    if (SOURCE)
    {
        if (sSource == "") joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString("default"));
        else joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(" :: " + sSource + " :: "));
    }

    return joOutputUnit;
}

json schema_output_UpdateOutputUnit(json joOutputUnit)
{
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);

    return joOutputUnit;
}

/// @private Insert an error object into the parent node's errors array.
json schema_output_InsertParentError(json joOutputUnit, json joError, string sSource = "")
{
    if (JsonGetType(joError) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    if (JsonGetType(jaErrors) != JSON_TYPE_ARRAY)
        jaErrors = JsonArray();

    jaErrors = JsonArrayInsert(jaErrors, joError);
    joOutputUnit = JsonObjectSet(joOutputUnit, "errors", jaErrors);
    joOutputUnit = schema_output_SetValid(joOutputUnit, FALSE);

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joOutputUnit); 
    return joOutputUnit;
}

/// @private Insert an annotation object into the parent node's annotations array.
json schema_output_InsertParentAnnotation(json joOutputUnit, json joAnnotation, string sSource = "")
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

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

    return joOutputUnit;
}

/// @todo
///     [ ] how do we handle failed keyword validations that may not fail the entire schema?

/// @private Insert an error string in an output unit.
json schema_output_InsertChildError(json joOutputUnit, string sError, string sSource = "")
{
    joOutputUnit = JsonObjectSet(joOutputUnit, "error", JsonString(sError));
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

    return schema_output_SetValid(joOutputUnit, FALSE);
}

/// @private Insert an annotation key:value pair into an output unit.
json schema_output_InsertChildAnnotation(json joOutputUnit, string sKey, json jValue, string sSource = "")
{
    joOutputUnit = JsonObjectSet(joOutputUnit, sKey, jValue);
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

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
            numbers(n) AS (
                SELECT 0
                UNION ALL
                SELECT n + 1 FROM numbers WHERE n + 1 < json_array_length(:criteria)
            ),
            pairs AS (
                SELECT n,
                    json_extract(:match, '$[' || n || ']') AS t,
                    json_extract(:criteria, '$[' || n || ']') AS c
                FROM numbers
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
            END
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

    string sSource = __FUNCTION__;
    string sKeyword = "type";

    int nTypeType = JsonGetType(jSchema);
    if (nTypeType == JSON_TYPE_STRING)
    {
        int nInstanceType = JsonGetType(jInstance);

        if (JsonGetString(jSchema) == "number")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
                return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource + " (number)");
        }
        else if (JsonGetString(jSchema) == "integer")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
            {
                float f = JsonGetFloat(jInstance);

                if (IntToFloat(FloatToInt(f)) == f)
                    return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource + " (integer)");
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
                return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource + " (other)");
        }
    }
    else if (nTypeType == JSON_TYPE_ARRAY)
    {
        int i; for (; i < JsonGetLength(jSchema); i++)
        {
            json joValidate = schema_validate_Type(jInstance, JsonArrayGet(jSchema, i));
            if (schema_output_GetValid(joValidate))
                joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, joValidate, sSource + " (array)");
        }
    }

    json jaAnnotations = JsonObjectGet(joOutputUnit, "annotations");
    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL || JsonGetLength(jaAnnotations) == 0)
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource + " (error aggregation)");
    else if (nTypeType == JSON_TYPE_ARRAY && JsonGetLength(jaAnnotations) > 0)
        return schema_output_InsertChildAnnotation(schema_output_GetOutputUnit(), sKeyword, jSchema, sSource + " (annotation aggregation)");

    return joOutputUnit;
}

/// @brief Validates the global "enum" and "const" keywords.
/// @param jInstance The instance to validate.
/// @param jSchema The array of valid elements for enum/const. Assumed to be validated against the metaschema.
/// @returns An output object containing the validation result.
/// @note Due to NWN's nlohmann::json implementation, JsonFind() conducts a
///     deep comparison of the instance and enum/const values; separate handling
///     for the various json types is not required.
json schema_validate_enum(json jInstance, json jSchema, string sKeyword)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    string sSource = __FUNCTION__;

    if (JsonGetType(JsonFind(jSchema, jInstance)) == JSON_TYPE_NULL)
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource + " (null)");
    else
    {
        sSource += " (" + sKeyword + ")";

        if (sKeyword == "enum")
            return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
        else
            return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonArrayGet(jSchema, 0), sSource);
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

    string sSource = __FUNCTION__;
    string sKeyword = "minLength";

    /// @note minLength is ignored for non-string instances.
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    if (GetStringLength(JsonGetString(jsInstance)) * 1.0 >= JsonGetFloat(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @brief Validates the string "maxLength" keyword.
/// @param jsInstance The instance to validate.
/// @param jSchema The schema value for "maxLength" (assumed to be a non-negative integer).
/// @returns An output object containing the validation result.
json schema_validate_MaxLength(json jsInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    
    string sSource = __FUNCTION__;
    string sKeyword = "maxLength";

    /// @note maxLength is ignored for non-string instances.
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    if (GetStringLength(JsonGetString(jsInstance)) <= JsonGetInt(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @brief Validates the string "pattern" keyword.
/// @param jsInstance The instance to validate.
/// @param jSchema The schema value for "pattern".
/// @returns An output object containing the validation result.
json schema_validate_Pattern(json jsInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    
    string sSource = __FUNCTION__;
    string sKeyword = "pattern";

    /// @note pattern is ignored for non-string instances.
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    if (RegExpMatch(JsonGetString(jSchema), JsonGetString(jsInstance)) != JsonArray())
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
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
        return schema_output_InsertChildAnnotation(joOutputUnit, "format", jSchema);
    else
        return schema_output_InsertChildError(schema_output_SetValid(joOutputUnit, FALSE), "instance does not match format: " + sFormat);
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

    string sFunction = __FUNCTION__;
    
    /// @note minimum and exclusiveMinimum are ignored for non-number instances.
    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
    {
        string sKeyword;
        if (JsonGetType(jMinimum) != JSON_TYPE_NULL)
            sKeyword = "minimum";
        else if (JsonGetType(jExclusiveMinimum) != JSON_TYPE_NULL)
            sKeyword = "exclusiveMinimum";

        schema_scope_PushSchemaPath(sKeyword);
        jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sFunction));
        schema_scope_PopSchemaPath();
    }
    else
    {
        string sKeyword = "minimum";
        schema_scope_PushSchemaPath(sKeyword);

        /// @note Validate minimum independently from exclusiveMinimum.
        int nMinimumType = JsonGetType(jMinimum);
        if (nMinimumType == JSON_TYPE_INTEGER || nMinimumType == JSON_TYPE_FLOAT)
        {
            string sSource = sFunction + " (" + sKeyword + ")";

            if (JsonGetFloat(jInstance) >= JsonGetFloat(jMinimum))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jMinimum, sSource));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource));
        }

        sKeyword = "exlusiveMinimum";
        schema_scope_ReplaceSchemaPath(sKeyword);

        int nExclusiveMinimumType = JsonGetType(jExclusiveMinimum);
        if (nExclusiveMinimumType == JSON_TYPE_BOOL)
        {
            /// @note In early drafts, exclusiveMinimum is a boolean value and is dependent on minimum.  If
            ///     minimum is missing, exclusiveMinimum is ignored, otherwise, it is evaluated independently.
            if (nMinimumType == JSON_TYPE_INTEGER || nMinimumType == JSON_TYPE_FLOAT)
            {
                string sSource = sFunction + " (" + sKeyword + ")(bool)";

                if (jExclusiveMinimum == JSON_TRUE && JsonGetFloat(jInstance) > JsonGetFloat(jMinimum) ||
                    jExclusiveMinimum == JSON_FALSE && JsonGetFloat(jInstance) >= JsonGetFloat(jMinimum))
                {
                    jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jExclusiveMinimum, sSource));
                }
                else
                    jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource));
            }
        }
        else if (nExclusiveMinimumType == JSON_TYPE_INTEGER || nExclusiveMinimumType == JSON_TYPE_FLOAT)
        {
            string sSource = sFunction + " (" + sKeyword + ")";

            /// @note In later drafts, exclusiveMinimum is a number and is validated independently of minimum.
            if (JsonGetFloat(jInstance) > JsonGetFloat(jExclusiveMinimum))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jExclusiveMinimum, sSource));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource));
        }

        schema_scope_PopSchemaPath();
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

    string sFunction = __FUNCTION__;

    /// @note maximum and exclusiveMaximum are ignored for non-number instances.
    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
    {
        string sKeyword;
        if (JsonGetType(jMaximum) != JSON_TYPE_NULL)
            sKeyword = "maximum";
        else if (JsonGetType(jExclusiveMaximum) != JSON_TYPE_NULL)
            sKeyword = "exclusiveMaximum";

        schema_scope_PushSchemaPath(sKeyword);
        jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sFunction));
        schema_scope_PopSchemaPath();
    }
    else
    {
        string sKeyword = "maximum";
        schema_scope_PushSchemaPath(sKeyword);

        string sSource = sFunction + " (" + sKeyword + ")";

        /// @note Validate maximum independently from exclusiveMaximum.
        int nMaximumType = JsonGetType(jMaximum);
        if (nMaximumType == JSON_TYPE_INTEGER || nMaximumType == JSON_TYPE_FLOAT)
        {
            if (JsonGetFloat(jInstance) <= JsonGetFloat(jMaximum))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jMaximum, sSource));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource));
        }

        sKeyword = "exclusiveMaximum";
        schema_scope_ReplaceSchemaPath(sKeyword);

        int nExclusiveMaximumType = JsonGetType(jExclusiveMaximum);
        if (nExclusiveMaximumType == JSON_TYPE_BOOL)
        {
            /// @note In early drafts, exclusiveMaximum is a boolean value and is dependent on maximum.  If
            ///     maximum is missing, exclusiveMaximum is ignored, otherwise, it is evaluated independently.
            if (nMaximumType == JSON_TYPE_INTEGER || nMaximumType == JSON_TYPE_FLOAT)
            {
                string sSource = sFunction + " (" + sKeyword + ")(bool)";
                
                if (jExclusiveMaximum == JSON_TRUE && JsonGetFloat(jInstance) < JsonGetFloat(jMaximum) ||
                    jExclusiveMaximum == JSON_FALSE && JsonGetFloat(jInstance) <= JsonGetFloat(jMaximum))
                {
                    jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jExclusiveMaximum, sSource));
                }
                else
                    jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource));
            }
        }
        else if (nExclusiveMaximumType == JSON_TYPE_INTEGER || nExclusiveMaximumType == JSON_TYPE_FLOAT)
        {
            /// @note In later drafts, exclusiveMaximum is a number and is validated independently of maximum.
            if (JsonGetFloat(jInstance) < JsonGetFloat(jExclusiveMaximum))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jExclusiveMaximum, sSource));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource));
        }

        schema_scope_PopSchemaPath();
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
    string sSource = __FUNCTION__;
    string sKeyword = "multipleOf";

    /// @note multipleOf is ignored for non-number instances.
    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    float fMultiple = JsonGetFloat(jInstance) / JsonGetFloat(jSchema);
    if (fabs(fMultiple - IntToFloat(FloatToInt(fMultiple))) < 0.00001)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @private Validates the array "minItems" keyword.
/// @param jaInstance The instance to validate.
/// @param jSchema The schema value for "minItems".
/// @returns An output object containing the validation result.
json schema_validate_MinItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "minItems";

    /// @note minItems is ignored for non-array instances.
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    if (JsonGetLength(jaInstance) >= JsonGetInt(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @private Validates the array "maxItems" keyword.
/// @param jaInstance The instance to validate.
/// @param jSchema The schema value for "maxItems".
/// @returns An output object containing the validation result.
json schema_validate_MaxItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "maxItems";

    /// @note maxItems is ignored for non-array instances.
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    if (JsonGetLength(jaInstance) <= JsonGetInt(jSchema))
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @private Validates the array "uniqueItems" keyword.
/// @param jaInstance The instance to validate.
/// @param jSchema The schema value for "uniqueItems".
/// @returns An output object containing the validation result.
json schema_validate_UniqueItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "uniqueItems";

    /// @note uniqueItems is ignored for non-array instances.
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource + " (instance type)");

    if (jSchema == JSON_FALSE)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource + " (false)");

    if (JsonGetLength(jaInstance) == JsonGetLength(JsonArrayTransform(jaInstance, JSON_ARRAY_UNIQUE)))
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @todo
///     [ ] Change joItems to jItems since it can support old drafts that aren't objects?
///     [ ] Check error message/output unit return during testing.  This might not be the right message
///         All results of schema_core_Validate will be a full node, so this node object must be inserted
///         into the parent node for the evaluation?  How ill this output be structured? Maybe an array of
///         outputs that's parsed when returning to _validate?

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
    string sFunction = __FUNCTION__;

    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertChildAnnotation(schema_output_GetOutputUnit(__FUNCTION__), "instance", JsonString("not evaluated"), sFunction);

    int nInstanceLength = JsonGetLength(jaInstance);
    //json jaEvaluatedIndices = JsonArray();

    /// @note When an instance item is evaluated by any keyword method, it must be marked as evaluated to
    ///     ensure unevaluatedItems only evaluates truly unevaluated items.  To track evaluated indexes,
    ///     create an array of all instance indexes.  As various keywords evaluated instance items, those
    ///     item indexes will be removed from this array.
    json jaUnevaluatedIndexes = JsonArray();
    if (nInstanceLength > 0)
    {
        int i; for (; i < nInstanceLength; i++)
            jaUnevaluatedIndexes = JsonArrayInsert(jaUnevaluatedIndexes, JsonInt(i));
    }

    /// @brief prefixItems.  The value of this keyword must be a non-empty array of valid schema.  prefixItems
    ///     is a tuple validation, comparing each item in the instance array against the corresponding schema
    ///     item from the prefixItems array.
    /// @note If prefixItems.length > instance.length, excess prefixItem schema are ignored.
    /// @note If prefixItems.length < instance.length, excess instance items are not evaluated by prefixItems.

    /// @brief items.  When the value of this keyword is an array, items is a tuple validation, comparing each
    ///     item in the instance array against the corresponding schema item in the items array.
    /// @note If items.length > instance.length, excess items schema are ignored.
    /// @note If items.length < instance.length, excess instance items are not evaluated by items.
    /// @note Only items arrays are handled here.  When items is a boolean or object, it is handled below.

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
        schema_scope_PushSchemaPath(sKeyword);

        string sSource = sFunction + " (" + sKeyword + ")";
        json joKeywordOutputUnit = schema_output_GetOutputUnit(sKeyword);
       
        int i; for (; i < nSchemasLength && i < nInstanceLength; i++)
        {
            schema_scope_PushSchemaPath(IntToString(i));
            schema_scope_PushInstancePath(IntToString(i));

            json joTupleSchema = JsonArrayGet(jSchemas, i);
            json joResult = schema_core_Validate(JsonArrayGet(jaInstance, i), joTupleSchema);

            if (schema_output_GetValid(joResult))
                joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult, sSource);
            else
                joKeywordOutputUnit = schema_output_InsertParentError(joKeywordOutputUnit, joResult, sSource);

            //jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonInt(i));

            schema_scope_PopInstancePath();
            schema_scope_PopSchemaPath();
        }

        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief items.  When the value of this keyword is a boolean or object, the items subschema is
    ///     applied to all instance items at indexes greater than the length of prefixItems.
    int nKeywordType = JsonGetType(jItems);
    if (nKeywordType == JSON_TYPE_BOOL)
    {
        /// @note If jItems = true, all unevalauted instance items are considered to have passed 
        ///     validation and are considered evaluated.
        /// @note If jItems = false, all unevaluated instance items are considered to have failed
        ///     validation and are considered evaluated.
        string sKeyword = "items";
        string sSource = sFunction + " (" + sKeyword + ")";

        schema_scope_PushSchemaPath("items");
        json joKeywordOutputUnit = schema_output_GetOutputUnit();

        if (jItems == JSON_TRUE || nInstanceLength == 0)
            joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, jItems, sSource);
        else if (jItems == JSON_FALSE)
        {
            if (nSchemasLength < nInstanceLength)
                joKeywordOutputUnit = schema_output_InsertChildError(joKeywordOutputUnit, "undefined items are not allowed", sSource);
            else
                joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, jItems, sSource);
        }

        //int i; for (i = nSchemasLength; i < nInstanceLength; i++)
        //    jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonInt(i));

        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        schema_scope_PopSchemaPath();
    }
    else if (nKeywordType == JSON_TYPE_OBJECT)
    {
        string sKeyword = "items";
        string sSource = sFunction + " (" + sKeyword + ")";

        schema_scope_PushSchemaPath(sKeyword);
        json joKeywordOutputUnit = schema_output_GetOutputUnit();

        /// @note jItems = {} is functionally identical to jItems = true.
        if (jItems == JsonArray())
            joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, jItems, sSource);
        else
        {
            int i; for (i = nSchemasLength; i < nInstanceLength; i++)
            {
                schema_scope_PushInstancePath(IntToString(i));

                json jItem = JsonArrayGet(jaInstance, i);
                json joResult = schema_core_Validate(jItem, jItems);

                if (schema_output_GetValid(joResult))
                    joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult);
                else
                    joKeywordOutputUnit = schema_output_InsertParentError(joKeywordOutputUnit, joResult);

                //jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonInt(i));

                schema_scope_PopInstancePath();
            }
        }

        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief contains.  The value of "contains" must be a valid schema.  Validation occurs
    ///     against all instance items, including those previously evaluated by items and
    ///     prefixItems.  An instance array is valid against contains if at least one of the
    ///     instance array's item is valid against the contains schema.
    /// @note If contains = true, the instance array is considered valid if the instance array
    ///     has at least "minContains" items and no more than "maxContains" items.  All instance
    ///     items are considered evaluated.
    /// @note If contains = false, the instance array is considered invalid (unless minContains = 0)
    ///     and no instance items are considered evaluated.
    /// @note Instance items which successfully validate against the "contains" schema are
    ///     considered evaluated; instance items that do not validate against the "contains"
    ///     schema are not considered evaluated.

    /// @brief minContains.  The value of "minContains" must be a non-negative integer.  This
    ///     keyword is ignored if "contains" is not present in the same schema object.  To
    ///     validate against "minContains", the instance array must have at least "minContains"
    ///     items that are valid against the "contains" schema.
    /// @note If minContains = 0, the instance array is considered valid against the "contains"
    ///     schema, even if no instance items can be validated against the "contains" schema.
    /// @note If minContains is ommitted, a default value of 1 is used.

    /// @brief maxContains.  The value of "maxContains" must be a non-negative integer.  This
    ///     keyword is ignore if "contains" is not present in the same schema object.  To
    ///     validate against "maxContains", the instance array must have no more than "maxContains"
    ///     items that are valid against the "contains" schema.
    
    sKeyword = "contains";

    nKeywordType = JsonGetType(joContains);
    if (nKeywordType != JSON_TYPE_NULL)
    {
        string sSource = sFunction + " (" + sKeyword + ")";

        schema_scope_PushSchemaPath(sKeyword);

        json joKeywordOutputUnit = schema_output_GetOutputUnit();
        json jaContainsMatched = JsonArray();
        
        int nMatches;
        int nMinContains = JsonGetType(jiMinContains) != JSON_TYPE_NULL ? JsonGetInt(jiMinContains) : -1;
        int nMaxContains = JsonGetType(jiMinContains) != JSON_TYPE_NULL ? JsonGetInt(jiMaxContains) : -1;
        
        if (nKeywordType == JSON_TYPE_BOOL)
        {
            if (joContains == JSON_TRUE)
            {
                /// @note If contains = true, the following conditionals satsify validation:
                ///     - instance.length >= 1; [min|max]Contains is not specified
                ///     - minContains = 0
                ///     - maxContains = 0 && instance.length = 0
                ///     - minContains <= instance.length <= maxContains
                ///     - minContains <= instance.length; maxContains is not specified
                ///     - 1 <= instance.length <= maxContains; minContains is not specified
                if (
                    (nInstanceLength >= 1 && nMinContains == -1 && nMaxContains == -1) ||
                    (nMinContains == 0) ||
                    (nMaxContains == 0 && nInstanceLength == 0) ||
                    (nMinContains > -1 && nMaxContains > -1 && nInstanceLength >= nMinContains && nInstanceLength <= nMaxContains) ||
                    (nMinContains > -1 && nMaxContains == -1 && nInstanceLength >= nMinContains) ||
                    (nMaxContains > -1 && nMinContains == -1 && nInstanceLength >= 1 && nInstanceLength <= nMaxContains)
                )
                {
                    joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, joContains, sSource);
                    nMatches = JsonGetLength(jaUnevaluatedIndexes);
                    jaUnevaluatedIndexes = JsonArray();
                }
                else
                    joKeywordOutputUnit = schema_output_InsertChildError(joKeywordOutputUnit, "<validate_contains>", sSource);
            }
            else if (joContains == JSON_FALSE)
            {
                /// @note If contains = false, the following conditionals satisfy validation:
                ///     - minContains = 0
                ///     - maxContains = 0 && instance.length = 0
                if (
                    (nMinContains == 0) ||
                    (nMaxContains == 0 && nInstanceLength == 0)
                )
                {
                    joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, joContains, sSource);
                    nMatches = JsonGetLength(jaUnevaluatedIndexes);
                    jaUnevaluatedIndexes = JsonArray();
                }
                else
                    joKeywordOutputUnit = schema_output_InsertChildError(joKeywordOutputUnit, "<validate_contains>", sSource);
            }
        }
        else if (nKeywordType == JSON_TYPE_OBJECT)
        {
            if (nMinContains == 0)
                joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, joContains, sSource);
            else
            {
                int i; for (; i < nInstanceLength; i++)
                {
                    schema_scope_PushInstancePath(IntToString(i));

                    json joResult = schema_core_Validate(JsonArrayGet(jaInstance, i), joContains);
                    if (schema_output_GetValid(joResult))
                    {
                        nMatches++;
                        joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult);

                        json jIndex = JsonFind(jaUnevaluatedIndexes, JsonInt(i));
                        if (jIndex != JsonNull())
                            jaUnevaluatedIndexes = JsonArrayDel(jaUnevaluatedIndexes, JsonGetInt(jIndex));
                    }
                    else
                        joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult);

                    schema_scope_PopInstancePath();
                }

                if (
                    (nMatches < (nMinContains == -1 ? 1 : nMinContains)) ||
                    (nMaxContains != -1 && nMatches > nMaxContains)
                )
                {
                    joKeywordOutputUnit = schema_output_SetValid(joKeywordOutputUnit, FALSE);
                }
            }
        }

        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);

        sKeyword = "minContains";
        sSource = sFunction + " (" + sKeyword + ")";

        nKeywordType = JsonGetType(jiMinContains);
        if (nKeywordType == JSON_TYPE_INTEGER || nKeywordType == JSON_TYPE_FLOAT)
        {
            joKeywordOutputUnit = schema_output_GetOutputUnit();

            if (nMatches >= JsonGetInt(jiMinContains))
                joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, jiMinContains);
            else
                joKeywordOutputUnit = schema_output_InsertChildError(joKeywordOutputUnit, schema_output_GetErrorMessage("<validate_mincontains>"));

            jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        }

        sKeyword = "minContains";
        sSource = sFunction + " (" + sKeyword + ")";

        nKeywordType = JsonGetType(jiMaxContains);
        if (nKeywordType == JSON_TYPE_INTEGER || nKeywordType == JSON_TYPE_FLOAT)
        {
            joKeywordOutputUnit = schema_output_GetOutputUnit();

            if (nMatches <= JsonGetInt(jiMaxContains))
                joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, sKeyword, jiMaxContains);
            else
                joKeywordOutputUnit = schema_output_InsertChildError(joKeywordOutputUnit, schema_output_GetErrorMessage("<validate_maxcontains>"));

            jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        }

        schema_scope_PopSchemaPath();
    }

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
        json joChildOutputUnit, joOutputUnit = schema_output_GetOutputUnit("additional/unevaluatedItems");

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
                schema_scope_PushSchemaPath(IntToString(i));
                schema_scope_PushInstancePath(IntToString(i));

                //if (JsonFind(jaEvaluatedIndices, JsonInt(i)) == JsonNull())
                //{
                //    json jItem = JsonArrayGet(jaInstance, i);
                //    json jResult = schema_core_Validate(jItem, jSchemas);
//
                //    if (schema_output_GetValid(jResult))
                //        joChildOutputUnit = schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchemas);
                //    else
                //        joChildOutputUnit = schema_output_InsertChildError(joOutputUnit, "<validate_" + GetStringLowerCase(sKeyword) + ">");
//
                //    if (schema_output_GetValid(joChildOutputUnit))
                //        joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                //    else
                //        joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);
                //}

                schema_scope_PopInstancePath();
                schema_scope_PopSchemaPath();
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
    string sSource = __FUNCTION__;
    string sKeyword = "required";

    /// @note required is ignored for non-object instances.
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    json jaMissingProperties = JsonArray();
    json jaInstanceKeys = JsonObjectKeys(joInstance);
    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        json jProperty = JsonArrayGet(jSchema, i);
        if (JsonFind(jaInstanceKeys, jProperty) == JsonNull())
            jaMissingProperties = JsonArrayInsert(jaMissingProperties, jProperty);
    }

    if (JsonGetLength(jaMissingProperties) > 0)
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    else
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
}

/// @private Validates the object "minProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jSchema The schema value for "minProperties".
/// @returns An output object containing the validation result.
json schema_validate_MinProperties(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "minProperties";
    
    /// @note minProperties is ignored for non-object instances.
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);
    
    if (JsonGetLength(joInstance) < JsonGetInt(jSchema))
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    else
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
}

/// @private Validates the object "maxProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jSchema The schema value for "maxProperties".
/// @returns An output object containing the validation result.
json schema_validate_MaxProperties(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "minProperties";

    /// @note maxProperties is ignored for non-object instances.
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

    if (JsonGetLength(joInstance) > JsonGetInt(jSchema))
        return schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    else
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
}

/// @brief Validates the object "dependentRequired" keyword.
/// @param joInstance The object instance to validate.
/// @param joDependentRequired The schema value for "dependentRequired".
/// @returns An output object containing the validation result.
json schema_validate_DependentRequired(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "dependentRequired";

    /// @note dependentRequired is ignored for non-object instances.    
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource);

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
    string sFunction = __FUNCTION__;

    json joOutputUnit = schema_output_GetOutputUnit();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertChildAnnotation(schema_output_GetOutputUnit(), "properties", JsonString("keyword ignored due to instance type"));

    /// @brief Evaluated properties must be tracked to ensure only truly unevaluated properties will be
    ///     validated by unevaluatedProperties, if it exists.  Properties are considered evaluated if
    ///     processed by the following keywords (and in this order):
    ///         properties
    ///         patternProperties
    ///         additionalProperties
    ///         dependentSchemas (dependencies)
    ///         unevaluatedProperties
    json jaEvaluatedProperties = JsonArray();
    json jaInstanceKeys = JsonObjectKeys(joInstance);
    json jaPropertyKeys = JsonObjectKeys(joProperties);

    int nInstanceKeys = JsonGetLength(jaInstanceKeys);

    if (JsonGetType(joProperties) == JSON_TYPE_OBJECT)
    {
        /// @brief properties.  The schema value of "properties" must be an object and all values within
        ///     must be valid schema.  For each property name that appears in both the instance and
        ///     schema, the child instance is validated against the corresponding schema.
        /// @note If properties = {}, the validation automatically succeeds.
        /// @note All validated properties are considered evaluated, whether or not they pass validation.
        schema_scope_PushSchemaPath("properties");

        json joKeywordOutputUnit = schema_output_GetOutputUnit("properties");
        
        if (joProperties == JsonObject())
            joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, "properties", joProperties);
        else
        {
            int i; for (; i < nInstanceKeys; i++)
            {
                string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                schema_scope_PushInstancePath(sInstanceKey);

                if (JsonFind(jaPropertyKeys, JsonString(sInstanceKey)) != JsonNull())
                {
                    schema_scope_PushSchemaPath(sInstanceKey);

                    json joResult = schema_core_Validate(JsonObjectGet(joInstance, sInstanceKey), JsonObjectGet(joProperties, sInstanceKey));

                    if (schema_output_GetValid(joResult))
                        joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult);
                    else
                        joKeywordOutputUnit = schema_output_InsertParentError(joKeywordOutputUnit, joResult);                

                    jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sInstanceKey));

                    schema_scope_PopSchemaPath();
                }
                
                schema_scope_PopInstancePath();
            }
        }

        schema_scope_PopSchemaPath();
        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
    }

    if (JsonGetType(joPatternProperties) == JSON_TYPE_OBJECT)
    {
        /// @brief patternProperties.  The schema value of "patternProperties" must be an object.  The schema
        ///     property names should be valid ecma-262 regex patterns.  For each property name in the
        ///     instance that matches *any* regex pattern in the schema's property names, the child instance
        ///     is validated aginst the corresponding schema.
        /// @note If instance = {}, the validation automatically succeeds.
        /// @note if patternProperties = {}, the validation automatically succeeds.
        /// @note All instance property names that match schema property name regex patterns are considered
        ///     evaluated, whether or not they pass validation.
        /// @warning Evaluating valid regex patterns is beyond the scope of this system.

        schema_scope_PushSchemaPath("patternProperties");

        json joKeywordOutputUnit = schema_output_GetOutputUnit("patternProperties");
        json jaPatternKeys = JsonObjectKeys(joPatternProperties);
        
        string sSource = sFunction + " (patternProperties)";

        if (nInstanceKeys == 0 || joPatternProperties == JsonObject())
            joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, "patternProperties", joPatternProperties, sSource);
        else
        {
            int i; for (; i < nInstanceKeys; i++)
            {
                string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                schema_scope_PushInstancePath(sInstanceKey);

                int j; for (; j < JsonGetLength(jaPatternKeys); ++j)
                {
                    string sPattern = JsonGetString(JsonArrayGet(jaPatternKeys, j));
                    schema_scope_PushSchemaPath(sPattern);

                    json jaMatch = RegExpMatch(sPattern, sInstanceKey);
                    if (JsonGetType(jaMatch) != JSON_TYPE_NULL && jaMatch != JsonArray())
                    {
                        json joPatternSchema = JsonObjectGet(joPatternProperties, sPattern);
                        json joResult = schema_core_Validate(JsonObjectGet(joInstance, sInstanceKey), joPatternSchema);

                        if (schema_output_GetValid(joResult))
                            joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult, sSource);
                        else
                            joKeywordOutputUnit = schema_output_InsertParentError(joKeywordOutputUnit, joResult, sSource);

                        jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sInstanceKey));
                    }

                    schema_scope_PopSchemaPath();
                }

                schema_scope_PopInstancePath();
            }
        }

        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        schema_scope_PopSchemaPath();
    }

    int nKeywordType = JsonGetType(jAdditionalProperties);
    if (nKeywordType == JSON_TYPE_OBJECT || nKeywordType == JSON_TYPE_BOOL)
    {
        /// @brief additionalProperties. The value of "additionalProperties" must be a valid schema.  Validation only
        ///     occurs against instance property names which were not evaluated by "properties" or "patternProperties".
        /// @note If additionalProperties = true, all unevaluated instance property names are considered to have passed
        ///     validation and are considered evaluated.
        /// @note If additionalProperties = false, all unevaluated instance property names are considered to have failed
        ///     validation are are considered evaluated.
        /// @note If additionalProperties = {}, unevaluated instance property names are not validated and are still
        ///     considered unevaluated.
        schema_scope_PushSchemaPath("additionalProperties");
        json joKeywordOutputUnit = schema_output_GetOutputUnit("additionalPropertiers");

        if (nKeywordType == JSON_TYPE_BOOL)
        {
            if (jAdditionalProperties == JSON_FALSE && JsonSetOp(jaInstanceKeys, JSON_SET_DIFFERENCE, jaEvaluatedProperties) != JsonArray())
                joKeywordOutputUnit = schema_output_InsertChildError(joKeywordOutputUnit, "additional properties not allowed");
            else if (jAdditionalProperties == JSON_TRUE)
                joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, "additionalProperties", jAdditionalProperties);

            /// @note Schema specification states that a present and boolean additionalProperties keyword
            ///     evaluates all remaining unevaluated properties.
            jaEvaluatedProperties = jaInstanceKeys;
        }
        else
        {
            /// @todo
            ///     [ ] shortcut an empty object?  If {}, we really just skip the entire validation and insert
            ///     and empty node that gives no information other than we looked at this node.

            json jaUnevaluatedKeys = JsonSetOp(jaInstanceKeys, JSON_SET_DIFFERENCE, jaEvaluatedProperties);
            int i; for (; i < JsonGetLength(jaUnevaluatedKeys); i++)
            {
                string sUnevaluatedKey = JsonGetString(JsonArrayGet(jaUnevaluatedKeys, i));
                schema_scope_PushInstancePath(sUnevaluatedKey);

                json joResult = schema_core_Validate(JsonObjectGet(joInstance, sUnevaluatedKey), jAdditionalProperties);

                if (schema_output_GetValid(joResult))
                    joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult);
                else
                    joKeywordOutputUnit = schema_output_InsertParentError(joKeywordOutputUnit, joResult);

                jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sUnevaluatedKey));

                schema_scope_PopInstancePath();
            }
        }
        
        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @todo
    ///     [ ] propertynames does not affect unevaluatedItems and is completely independent
    ///         move to its own function?
    // 5. propertyNames
    nKeywordType = JsonGetType(jPropertyNames);
    if (nKeywordType == JSON_TYPE_OBJECT || nKeywordType == JSON_TYPE_BOOL)
    {
        json joParentOutputUnit = schema_output_GetOutputUnit();

        if (nKeywordType == JSON_TYPE_BOOL)
        {
            if (jPropertyNames == JSON_FALSE)
            {
                if (nInstanceKeys == 0)
                    joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, schema_output_InsertChildAnnotation(joOutputUnit, "propertyNames", jPropertyNames));
                else if (nInstanceKeys > 0)
                    joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage("<validate_propertynames>")));
            }
        }
        else
        {
            if (nInstanceKeys == 0)
                joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, schema_output_InsertChildAnnotation(joOutputUnit, "propertyNames", jPropertyNames));
            else
            {
                int i; for (; i < nInstanceKeys; i++)
                {
                    json joChildOutputUnit = schema_output_GetOutputUnit();

                    string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                    schema_scope_PushInstancePath(sInstanceKey);

                    json joResult = schema_core_Validate(JsonString(sInstanceKey), jPropertyNames);

                    if (schema_output_GetValid(joResult))
                        joChildOutputUnit = schema_output_InsertChildAnnotation(joChildOutputUnit, "propertyNames", jPropertyNames);
                    else
                        joChildOutputUnit = schema_output_InsertChildError(joChildOutputUnit, schema_output_GetErrorMessage("<validate_propertynames>"));

                    if (schema_output_GetValid(joChildOutputUnit))
                        joParentOutputUnit = schema_output_InsertParentAnnotation(joParentOutputUnit, joChildOutputUnit);
                    else
                        joParentOutputUnit = schema_output_InsertParentError(joParentOutputUnit, joChildOutputUnit);

                    schema_scope_PopInstancePath();
                }
            }
        }

        if (JsonGetLength(JsonObjectGet(joParentOutputUnit, "annotations")) > 0 || JsonGetLength(JsonObjectGet(joParentOutputUnit, "errors")) > 0)
            jaOutput = JsonArrayInsert(jaOutput, joParentOutputUnit);
    }

    // 5.5 dependencies

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


    /// @todo
    ///     [ ] need logic for dependencies objects (dependentSchemas) v arrays (dependentRequired)
    ///     [ ] use a keyword string and existing dependencies keyword
    ///         if dependencies exists, set joDependentSchema = dependencies
    ///                                 set sKeyword = "dependencies"
    ///         when looping the dependent keys
    ///             if type = array, get results from dependentRequired
    ///             else type = object, get results from _Validate
    ///         instance for validation should be the entire object containing the dependencies keyword

    // 4. dependentSchemas
    if (JsonGetType(joDependentSchemas) == JSON_TYPE_OBJECT)
    {
        schema_scope_PushSchemaPath("dependentSchemas");
        json joKeywordOutputUnit = schema_output_GetOutputUnit("dependentSchemas");

        json jaDependentKeys = JsonObjectKeys(joDependentSchemas);
        int nDependentKeys = JsonGetLength(jaDependentKeys);
        
        int i; for (; i < nDependentKeys; i++)
        {
            string sDependentKey = JsonGetString(JsonArrayGet(jaDependentKeys, i));
            schema_scope_PushSchemaPath(sDependentKey);

            if (JsonFind(jaInstanceKeys, JsonString(sDependentKey)) != JsonNull())
            {
                json joDependentSchema = JsonObjectGet(joDependentSchemas, sDependentKey);
                json joResult = schema_core_Validate(joInstance, joDependentSchema);
           
                if (schema_output_GetValid(joResult))
                    joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult);
                else
                    joKeywordOutputUnit = schema_output_InsertParentError(joKeywordOutputUnit, joResult);

                /// @todo
                ///     [ ] Build the query that pulls all evaluated properties out of joResult;

                jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sDependentKey));
            }

            schema_scope_PopSchemaPath();
        }
        
        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief Validate all remaining unevaluated properties.
    nKeywordType = JsonGetType(jUnevaluatedProperties);
    if (nKeywordType == JSON_TYPE_OBJECT || nKeywordType == JSON_TYPE_BOOL)
    {
        schema_scope_PushSchemaPath("unevaluatedProperties");
        json joKeywordOutputUnit = schema_output_GetOutputUnit("unevalutedProperties");
        
        if (jUnevaluatedProperties == JsonObject())
            joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, "unevaluatedProperties", jaEvaluatedProperties);
        else if (nKeywordType == JSON_TYPE_BOOL)
        {
            if (jUnevaluatedProperties == JSON_FALSE && JsonSetOp(jaInstanceKeys, JSON_SET_DIFFERENCE, jaEvaluatedProperties) != JsonArray())
                joKeywordOutputUnit = schema_output_InsertChildError(joKeywordOutputUnit, "unevaluated properties disallowed");
            else
                joKeywordOutputUnit = schema_output_InsertChildAnnotation(joKeywordOutputUnit, "unevaluatedProperties", jaEvaluatedProperties);
        }
        else
        {
            json jaUnevaluatedKeys = JsonSetOp(jaInstanceKeys, JSON_SET_DIFFERENCE, jaEvaluatedProperties);
            int i; for (; i < JsonGetLength(jaUnevaluatedKeys); i++)
            {
                string sUnevaluatedKey = JsonGetString(JsonArrayGet(jaUnevaluatedKeys, i));
                schema_scope_PushInstancePath(sUnevaluatedKey);

                json joResult = schema_core_Validate(JsonObjectGet(joInstance, sUnevaluatedKey), jUnevaluatedProperties);
                
                if (schema_output_GetValid(joResult))
                    joKeywordOutputUnit = schema_output_InsertParentAnnotation(joKeywordOutputUnit, joResult);
                else
                    joKeywordOutputUnit = schema_output_InsertParentError(joKeywordOutputUnit, joResult);

                schema_scope_PopInstancePath();
            }
        }

        jaOutput = JsonArrayInsert(jaOutput, joKeywordOutputUnit);
        schema_scope_PopSchemaPath();
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
    json joResult = schema_core_Validate(jInstance, jSchema);
    string sSource = __FUNCTION__;

    if (schema_output_GetValid(joResult))
        return schema_output_InsertParentError(joOutputUnit, joResult, sSource);
    else
        return schema_output_InsertParentAnnotation(joOutputUnit, joResult, sSource);
}

/// @brief Validates the applicator "allOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "allOf".
/// @returns An output object containing the validation result.
json schema_validate_AllOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));

        if (schema_output_GetValid(joResult))
            joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, joResult, sSource);
        else
            joOutputUnit = schema_output_InsertParentError(joOutputUnit, joResult, sSource);

        schema_scope_PopSchemaPath();
    }

    return joOutputUnit;
}

/// @brief Validates the applicator "anyOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "anyOf".
/// @returns An output object containing the validation result.
json schema_validate_AnyOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaResults = JsonArray();

    string sSource = __FUNCTION__;

    int nMatches;

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        jaResults = JsonArrayInsert(jaResults, joResult);

        if (schema_output_GetValid(joResult))
            nMatches++;

        schema_scope_PopSchemaPath();
    }

    for (i = 0; i < JsonGetLength(jaResults); i++)
    {
        if (nMatches >= 1)
            joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, JsonArrayGet(jaResults, i), sSource);
        else
            joOutputUnit = schema_output_InsertParentError(joOutputUnit, JsonArrayGet(jaResults, i), sSource);
    }

    return joOutputUnit;
}

/// @brief Validates the applicator "oneOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "oneOf".
/// @returns An output object containing the validation result.
json schema_validate_OneOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaResults = JsonArray();

    string sSource = __FUNCTION__;

    int nMatches;

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        jaResults = JsonArrayInsert(jaResults, joResult);

        if (schema_output_GetValid(joResult))
            nMatches++;

        schema_scope_PopSchemaPath();
    }

    for (i = 0; i < JsonGetLength(jaResults); i++)
    {
        if (nMatches == 1)
            joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, JsonArrayGet(jaResults, i), sSource);
        else
            joOutputUnit = schema_output_InsertParentError(joOutputUnit, JsonArrayGet(jaResults, i), sSource);
    }

    return joOutputUnit;
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

    string sFunction = __FUNCTION__;
    string sKeyword = "if";

    schema_scope_PushSchemaPath(sKeyword);
    jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, joIf, sFunction + " (" + sKeyword + ")"));

    if (schema_output_GetValid(schema_core_Validate(jInstance, joIf)))
    {
        schema_scope_PopSchemaPath();

        if (JsonGetType(joThen) != JSON_TYPE_NULL)
        {
            sKeyword = "then";
            schema_scope_PushSchemaPath(sKeyword);
            
            if (schema_output_GetValid(schema_core_Validate(jInstance, joThen)))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, joThen));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sFunction + " (" + sKeyword + ")"));

            schema_scope_PopSchemaPath();
        }
    }
    else
    {
        schema_scope_PopSchemaPath();

        if (JsonGetType(joElse) != JSON_TYPE_NULL)
        {
            sKeyword = "else";
            schema_scope_PushSchemaPath(sKeyword);

            if (schema_output_GetValid(schema_core_Validate(jInstance, joElse)))
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildAnnotation(joOutputUnit, sKeyword, joElse));
            else
                jaOutput = JsonArrayInsert(jaOutput, schema_output_InsertChildError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sFunction + " (" + sKeyword + ")"));

            schema_scope_PopSchemaPath();
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
    ///     [ ] debug refs.  they're not evaluating correctly
    ///         This is likely because fragments aren't returning the schema appropraiately.  I assume
    ///         the original schema isn't saved anywhere, so there's nothing to referece.
    ///         Save the original schema into (maybe) lexical_scope[0] (?) since the 0-index is
    ///         ignored in this system, we can use it for whatever we want.
    
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
        else
        {
            schema_scope_PushSchemaPath(sKey);

            if      (sKey == "allOf")            {jResult = schema_validate_AllOf(jInstance, JsonObjectGet(joSchema, sKey));}
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

            schema_scope_PopSchemaPath();
        }

        int nResultType = JsonGetType(jResult);
        if (nResultType == JSON_TYPE_ARRAY)
        {
            /// @note Array results are returned from compound validation functions.  For classification
            ///     purposes, the entire result set is either an annotation or an error, regardless of
            ///     the mix.  A single error results in the entire set being classified as an error array.
            int nResultLength = JsonGetLength(jResult);
            int i; for (; i < nResultLength; i++)
            {
                if (!schema_output_GetValid(JsonArrayGet(jResult, i)))
                    break;
            }

            string sSource = __FUNCTION__ + " (array)";

            /// @note To ease processing, the entire array, which is returned as an array of output unit
            ///     objects, can be inserted as the appropriate array in the paretn output unit.
            if (i == nResultLength)
            {
                joOutputUnit = JsonObjectSet(joOutputUnit, "annotations", jResult);
                joOutputUnit = schema_output_SetValid(joOutputUnit, TRUE);
            }
            else
            {
                joOutputUnit = JsonObjectSet(joOutputUnit, "errors", jResult);
                joOutputUnit = schema_output_SetValid(joOutputUnit, FALSE);
            }

            if (SOURCE) joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

            /// @note Since schema_output_InsertParent* is not called here, the result must be
            ///     manually saved to ensure its availability to the calling functions.
            schema_output_SaveValidationResult(joOutputUnit);
        }
        else if (nResultType == JSON_TYPE_OBJECT)
        {
            /// @note Object results are return from singular validation functions.  Results are
            ///     returned with the appropriate classification, so the only processing required
            ///     is to insert them into the appropriate array in the parent output unit.
            string sSource = __FUNCTION__ + " (object)";

            if (schema_output_GetValid(jResult))
                joOutputUnit = schema_output_InsertParentAnnotation(joOutputUnit, jResult, sSource);
            else
                joOutputUnit = schema_output_InsertParentError(joOutputUnit, jResult, sSource);
        }
        else
        {
            jResult = JsonObjectSet(JsonObject(), "valid", JsonBool(TRUE));
            /// @todo
            ///     [ ] When integrating joResult, we'll make JsonNull() mean that the keyword is not handled and/or supported?
        }
    }

    if (bDynamicAnchor)
        schema_scope_PopDynamic();

    return joOutputUnit;
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

    return schema_output_GetValid(schema_output_GetValidationResult());
}

/*
    entry points need to:
    - schedule the variable destruction
    - call for schema validation
    - save the schema is valid and an id exists
*/
