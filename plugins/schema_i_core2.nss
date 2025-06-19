
#include "util_i_debug"
/// @todo debug functions ... probably get rid of these for production?
string schema_debug_JsonToType(json j)
{
    int nType = JsonGetType(j);
    // Returns a string representation of the JSON type
    switch (nType)
    {
        case JSON_TYPE_NULL: return "null";
        case JSON_TYPE_BOOL: return "boolean";
        case JSON_TYPE_INTEGER: return "integer";
        case JSON_TYPE_FLOAT: return "float";
        case JSON_TYPE_STRING: return "string";
        case JSON_TYPE_ARRAY: return "array";
        case JSON_TYPE_OBJECT: return "object";
        default: return "unknown";
    }

    return "";
}

json schema_core_Validate(json jInstance, json joSchema);

int schema_HasKey(json jo, string sKey)
{
    // Returns TRUE if the object has the specified key, FALSE otherwise
    return (JsonFind(jo, JsonString(sKey)) != JsonNull());
}

/// -----------------------------------------------------------------------------------------------
///                                         PATH MANAGEMENT
/// -----------------------------------------------------------------------------------------------
/// @brief Schema path management functions.  These functions provide a method for recording
///    the current path in a schema.  This data will primarily be used for providing
///    path information for error and annotation messages.

/// @brief Retrieve the schema path array.
json schema_path_Get()
{
    json jaPath = GetLocalJson(GetModule(), "SCHEMA_PATH");
    if (JsonGetType(jaPath) != JSON_TYPE_ARRAY)
        return JsonArray();

    return jaPath;
}

/// @brief Push a path into the schema path array.
/// @param jsPath JSON string containing the path.
/// @returns The updated path array.
json schema_path_Push(json jsPath)
{
    if (JsonGetType(jsPath) == JSON_TYPE_STRING)
    {
        json jaPath = JsonArrayInsert(schema_path_Get(), jsPath);
        SetLocalJson(GetModule(), "SCHEMA_PATH", jaPath);
        return jaPath;
    }

    return schema_path_Get();
}

/// @brief Pop the last path from the path array.
/// @returns The last path in the array, or an empty JSON string.
json schema_path_Pop()
{
    json jaPath = schema_path_Get();
    if (JsonGetLength(jaPath) > 0)
    {
        SetLocalJson(GetModule(), "SCHEMA_PATH", JsonArrayGetRange(jaPath, 0, JsonGetLength(jaPath) - 1));
        return JsonArrayGet(jaPath, JsonGetLength(jaPath) - 1);
    }

    return JsonString("");
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

int schema_output_GetValid(json joOutput)
{
    return (JsonObjectGet(joOutput, "valid") == JsonInt(1));
}

json schema_output_SetValid(json joOutput, int bValid = TRUE)
{
    return JsonObjectSet(joOutput, "valid", bValid ? JSON_TRUE : JSON_FALSE);
}

sqlquery schema_core_PrepareQuery(string s)
{
    return SqlPrepareQueryCampaign("schema_data", s);
}

/// @todo build schema_core_Reset()
/// @todo create a "core" section for the core functions
/// @todo check for existence of sFile and use backup json

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
json schema_output_GetMinimalObject(string sVerbosity = SCHEMA_OUTPUT_VERBOSE, string sFile = "output")
{
    string s = r"
        CREATE TABLE IF NOT EXISTS schema_output (
            verbosity TEXT NOT NULL,
            schema TEXT NOT NULL,
            output TEXT NOT NULL DEFAULT '{}',
            PRIMARY KEY (verbosity, schema)
        );
    ";
    SqlStep(schema_core_PrepareQuery(s));

    json jFile = JsonParse(ResManGetFileContents(sFile, RESTYPE_TXT));
    s = r"
        SELECT output
        FROM schema_output
        WHERE verbosity = :output_verbosity
            AND schema = :output_schema;
    ";

    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":output_verbosity", sVerbosity);
    SqlBindJson(q, ":output_schema", jFile);

    if (SqlStep(q))
    {
        json jOutput = SqlGetJson(q, 0);
        if (JsonGetType(jOutput) == JSON_TYPE_OBJECT)
            return jOutput;
    }

    s = r"
        WITH RECURSIVE
            input_data AS (
                SELECT 
                    :output_schema AS schema,
                    :output_verbosity AS verbosity
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
                            'object'  -- Default to object if type not specified
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

    q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindJson(q, ":output_schema", jFile);
    SqlBindString(q, ":output_verbosity", sVerbosity);

    if (SqlStep(q))
    {
        json jOutput = SqlGetJson(q, 0);

        string s = r"
            INSERT INTO schema_output (verbosity, schema, output)
            VALUES (:output_verbosity, :output_schema, :output_data)
            ON CONFLICT(verbosity, schema) DO UPDATE SET
                output = :output_data;
        ";
        sqlquery q = schema_core_PrepareQuery(s);
        SqlBindString(q, ":output_verbosity", sVerbosity);
        SqlBindJson(q, ":output_schema", jFile);
        SqlBindJson(q, ":output_data", jOutput);

        SqlStep(q);

        return jOutput;
    }

    return JsonObject();
}

json schema_output_InsertError(json joOutput, string sError)
{
    if (sError == "")
        return joOutput;

    json jsError = JsonObjectGet(joOutput, "error");
    json jaErrors = JsonObjectGet(joOutput, "errors");

    if (JsonGetType(jsError) == JSON_TYPE_STRING)
    {
        jaErrors = JsonArrayInsert(JsonArray(), joOutput);
        joOutput = schema_output_SetValid(schema_output_GetMinimalObject(), FALSE);
        return JsonObjectSet(joOutput, "errors", jaErrors);
    }

    if (JsonGetType(jaErrors) == JSON_TYPE_ARRAY)
    {
        json joError = schema_output_SetValid(schema_output_GetMinimalObject(), FALSE);
        jaErrors = JsonArrayInsert(jaErrors, joError);
        return JsonObjectSet(joOutput, "errors", jaErrors);
    }

    if (JsonGetType(jsError) == JSON_TYPE_NULL && JsonGetType(jaErrors) == JSON_TYPE_NULL)
        return schema_output_SetValid(JsonObjectSet(joOutput, "error", JsonString(sError)), FALSE);

    return joOutput;
}

json schema_output_InsertAnnotation(json joOutput, string sKey, json jValue)
{
    json jaAnnotations = JsonObjectGet(joOutput, "annotations");
    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL)
        jaAnnotations = JsonArray();

    json joAnnotation = JsonObjectSet(schema_output_GetMinimalObject(), sKey, jValue);
    return JsonObjectSet(joOutput, "annotations", JsonArrayInsert(jaAnnotations, joAnnotation));
}

/// @todo this should be a convenience function to turn schema_output_Flag into an easily
///     accessible boolean value.  Move this out of this section and into the main
///     function area.
/// @todo make this a user-accessible function with a better name?
int schema_output_Valid(json joOutput)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT)
        return FALSE;

    if (JsonFind(joOutput, JsonString("valid")) == JsonNull())
        return FALSE;

    return schema_output_GetValid(joOutput);
}

json schema_output_Flag(json joOutput)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT)
        return JSON_NULL;

    if (JsonFind(joOutput, JsonString("valid")) == JsonNull())
        return JSON_NULL;

    return JsonObjectSet(JsonObject(), "valid", JsonObjectGet(joOutput, "valid"));
}

json schema_output_Basic(json joOutput)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT)
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

    sqlquery q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindJson(q, ":output", joOutput);

    return SqlStep(q) ? SqlGetJson(q, 0) : JSON_NULL;
}

/// @todo this output still needs work to remove any valid results entries as well as
///       collapsing/removing as required by json-schema.org
json schema_output_Detailed(json joOutput)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT)
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

    sqlquery q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindJson(q, ":output", joOutput);

    return SqlStep(q) ? SqlGetJson(q, 0) : JSON_NULL;
}

/// -----------------------------------------------------------------------------------------------
///                                     REFERENCE MANAGEMENT
/// -----------------------------------------------------------------------------------------------
/// @brief Schema reference management functions.  These functions provide a method for identifying,
///     resolving and utilizing $anchor, $dynamicAnchor, $ref and $dynamicRef keywords.

/// @todo this needs to be ResolveRef and ResolveDynamicRef (?)
json schema_reference_ResolveAnchor(json joSchema, string sAnchor)
{
    /// @todo provide a real feedback message
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

    sqlquery q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindString(q, ":anchor", sAnchor);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
}

/// @todo serious work in progress here.
///  need to know where to start from to make this works, so we'd have to
///  record pathing as the schema is descended into/out of.
json schema_reference_ResolveDynamicAnchor(json joSchema, string sAnchor)
{
    /// @todo provide a real feedback message
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT || sAnchor == "")
        return JsonNull();

    string s = r"
        WITH
            schema_tree AS (
                SELECT * FROM schema_table, json_tree(schema)
            ),
            ancestors(id, parent, depth) AS (
                SELECT id, parent, 0 FROM schema_tree WHERE id = 24
                UNION ALL
                SELECT st.id, st.parent, a.depth + 1
                FROM schema_tree st
                JOIN ancestors a ON st.id = a.parent
                WHERE st.parent IS NOT NULL
            ),
            closest_anchor AS (
                SELECT st.parent AS object_id, st.path, a.depth
                FROM schema_tree st
                JOIN ancestors a ON st.parent = a.id
                WHERE st.key = '$dynamicAnchor'
                AND st.atom = 'optionLevel'
                ORDER BY a.depth ASC  -- Closest ancestor first!
                LIMIT 1
            )

        SELECT
            json_extract(schema, '$' || substr(ca.path, 2)) AS object
        FROM
            schema_table, closest_anchor ca;
    ";

    sqlquery q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindString(q, ":anchor", sAnchor);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
}

/// -----------------------------------------------------------------------------------------------
///                                     KEYWORD VALIDATION
/// -----------------------------------------------------------------------------------------------

/// @brief Validates the global "type" keyword.
/// @param jInstance The instance to validate.
/// @param jType The schema value for "type".
/// @returns An output object containing the validation result.
json schema_validate_Type(json jInstance, json jType)
{
    json joOutput = schema_output_GetMinimalObject();
    int nInstanceType = JsonGetType(jInstance);
    int nTypeType = JsonGetType(jType);

    if (nTypeType == JSON_TYPE_STRING)
    {
        if (JsonGetString(jType) == "number")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
                return schema_output_InsertAnnotation(joOutput, "type", jType);
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

            json jiFind = JsonFind(jaTypes, jType);
            if (JsonGetType(jiFind) != JSON_TYPE_NULL && JsonGetInt(jiFind) == nInstanceType)
                return schema_output_InsertAnnotation(joOutput, "type", jType);
        }
    }
    else if (nTypeType == JSON_TYPE_ARRAY)
    {
        int i; for (; i < JsonGetLength(jType); i++)
        {
            json joValidate = schema_validate_Type(jInstance, JsonArrayGet(jType, i));
            if (schema_output_GetValid(joValidate))
                joOutput = joValidate;
        }
    }

    json jaAnnotations = JsonObjectGet(joOutput, "annotations");
    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL || JsonGetLength(jaAnnotations) == 0)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_type>"));
    else if (nTypeType == JSON_TYPE_ARRAY && JsonGetLength(jaAnnotations) > 0)
        return schema_output_InsertAnnotation(schema_output_GetMinimalObject(), "type", jType);

    return joOutput;
}

/// @brief Validates the global "enum" and "const" keywords.
/// @param jInstance The instance to validate.
/// @param jaEnum The array of valid elements for enum/const. Assumed to be validated against the metaschema.
/// @returns An output object containing the validation result.
/// @note Due to NWN's nlohmann::json implementation, JsonFind() conducts a
///     deep comparison of the instance and enum/const values; separate handling
///     for the various json types is not required.
json schema_validate_enum(json jInstance, json jaEnum, string sDescriptor)
{
    json joOutput = schema_output_GetMinimalObject();

    json jiIndex = JsonFind(jaEnum, jInstance);
    if (JsonGetType(jiIndex) == JSON_TYPE_NULL)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_enum>") + sDescriptor);
    else
    {
        if (sDescriptor == "enum")
            return schema_output_InsertAnnotation(joOutput, "enum", jaEnum);
        else
            return schema_output_InsertAnnotation(joOutput, "const", JsonArrayGet(jaEnum, 0));
    }
}

/// @brief Validates the global "enum" keyword.
/// @param jInstance The instance to validate.
/// @param jaEnum The schema value for "enum".
/// @returns An output object containing the validation result.
json schema_validate_Enum(json jInstance, json jaEnum)
{
    return schema_validate_enum(jInstance, jaEnum, "enum");
}

/// @brief Validates the global "const" keyword.
/// @param jInstance The instance to validate.
/// @param jConst The schema value for "const".
/// @returns An output object containing the validation result.
json schema_validate_Const(json jInstance, json jConst)
{
    return schema_validate_enum(jInstance, JsonArrayInsert(JsonArray(), jConst), "const");
}

/// @brief Validates the string "minLength" keyword.
/// @param jsInstance The instance to validate (assumed to be a string).
/// @param jiMinLength The schema value for "minLength" (assumed to be a non-negative integer).
/// @returns An output object containing the validation result.
json schema_validate_MinLength(json jsInstance, json jiMinLength)
{
    json joOutput = schema_output_GetMinimalObject();
    
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_string>"));

    int nMinLength = JsonGetInt(jiMinLength);
    if (GetStringLength(JsonGetString(jsInstance)) >= nMinLength)
        return schema_output_InsertAnnotation(joOutput, "minLength", jiMinLength);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_minlength>"));
}

/// @brief Validates the string "maxLength" keyword.
/// @param jsInstance The instance to validate (assumed to be a string).
/// @param jiMaxLength The schema value for "maxLength" (assumed to be a non-negative integer).
/// @returns An output object containing the validation result.
json schema_validate_MaxLength(json jsInstance, json jiMaxLength)
{
    json joOutput = schema_output_GetMinimalObject();
    
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_string>"));

    int nMaxLength = JsonGetInt(jiMaxLength);
    if (GetStringLength(JsonGetString(jsInstance)) <= nMaxLength)
        return schema_output_InsertAnnotation(joOutput, "maxLength", jiMaxLength);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_maxlength>"));
}

/// @brief Validates the string "pattern" keyword.
/// @param jsInstance The instance to validate.
/// @param jsPattern The schema value for "pattern".
/// @returns An output object containing the validation result.
json schema_validate_Pattern(json jsInstance, json jsPattern)
{
    json joOutput = schema_output_GetMinimalObject();
    
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_string>"));

    if (RegExpMatch(JsonGetString(jsPattern), JsonGetString(jsInstance)) != JsonArray())
        return schema_output_InsertAnnotation(joOutput, "pattern", jsPattern);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_pattern>"));
}
    
/// @brief Validates the string "format" keyword.
/// @param jInstance The instance to validate.
/// @param jFormat The schema value for "format" (a string).
/// @returns An output object containing the validation result.
json schema_validate_Format(json jInstance, json jFormat)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(jInstance) != JSON_TYPE_STRING)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_string>"));

    string sInstance = JsonGetString(jInstance);
    string sFormat = JsonGetString(jFormat);
    int bValid = FALSE;

    if (sFormat == "email")    {
        bValid = RegExpMatch("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", sInstance) != JsonArray();
    }
    else if (sFormat == "hostname")
    {
        if (GetStringLength(sInstance) <= 253)
            bValid = RegExpMatch("^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", sInstance) != JsonArray();
    }
    else if (sFormat == "ipv4")
    {
        /// @todo fix this
        bValid = FALSE;
//        bValid = RegExpMatch("^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\."
//                             "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\."
//                             "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\."
//                             "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", sInstance) != JsonArray();
    }
    else if (sFormat == "ipv6")
    {
        bValid = RegExpMatch("^([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}$", sInstance) != JsonArray()
              || RegExpMatch("^::([0-9A-Fa-f]{1,4}:){0,5}[0-9A-Fa-f]{1,4}$", sInstance) != JsonArray()
              || RegExpMatch("^([0-9A-Fa-f]{1,4}:){1,6}:$", sInstance) != JsonArray();
    }
    else if (sFormat == "uri")
    {
        bValid = RegExpMatch("^[a-zA-Z][a-zA-Z0-9+.-]*:[^\\s]*$", sInstance) != JsonArray();
    }
    else if (sFormat == "uri-reference")
    {
        bValid = (sInstance == "")
              || RegExpMatch("^[a-zA-Z][a-zA-Z0-9+.-]*:[^\\s]*$", sInstance) != JsonArray()
              || RegExpMatch("^[/?#]", sInstance) != JsonArray();
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
        bValid = RegExpMatch("^\\d{4}-\\d{2}-\\d{2}$", sInstance) != JsonArray();
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
        bValid = RegExpMatch("^P(?!$)(\\d+Y)?(\\d+M)?(\\d+D)?(T(\\d+H)?(\\d+M)?(\\d+S)?)?$", sInstance) != JsonArray();
    }
    else if (sFormat == "json-pointer")
    {
        bValid = (sInstance == "") || RegExpMatch("^(/([^/~]|~[01])*)*$", sInstance) != JsonArray();
    }
    else if (sFormat == "relative-json-pointer")
    {
        bValid = RegExpMatch("^[0-9]+(#|(/([^/~]|~[01])*)*)$", sInstance) != JsonArray();
    }
    else if (sFormat == "uuid")
    {
        bValid = RegExpMatch("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", sInstance) != JsonArray();
    }
    else if (sFormat == "regex")
    {
        bValid = (GetStringLength(sInstance) > 0);
    }
    else
    {
        return schema_output_InsertError(joOutput, "unsupported format: " + sFormat);
    }

    if (bValid)
        joOutput = schema_output_InsertAnnotation(joOutput, "format", jFormat);
    else
        return schema_output_InsertError(schema_output_SetValid(joOutput, FALSE), "instance does not match format: " + sFormat);

    return joOutput;
}

/// @brief Validates the number "minimum" keyword.
/// @param jInstance The instance to validate (assumed to be a number).
/// @param jMinimum The schema value for "minimum" (assumed to be a number).
/// @returns An output object containing the validation result.
json schema_validate_Minimum(json jInstance, json jMinimum)
{
    json joOutput = schema_output_GetMinimalObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_number>"));

    if (JsonGetFloat(jInstance) < JsonGetFloat(jMinimum))
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_minimum>"));
    else
        return schema_output_InsertAnnotation(joOutput, "minimum", jMinimum);
}

/// @brief Validates the number "exclusiveMinimum" keyword.
/// @param jInstance The instance to validate.
/// @param jExclusiveMinimum The schema value for "exclusiveMinimum".
/// @returns An output object containing the validation result.
json schema_validate_ExclusiveMinimum(json jInstance, json jExclusiveMinimum)
{
    json joOutput = schema_output_GetMinimalObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_number>"));

    if (JsonGetFloat(jInstance) <= JsonGetFloat(jExclusiveMinimum))
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_exclusiveminimum>"));
    else
        return schema_output_InsertAnnotation(joOutput, "exclusiveMinimum", jExclusiveMinimum);
}

/// @brief Validates the number "maximum" keyword.
/// @param jInstance The instance to validate.
/// @param jMaximum The schema value for "maximum".
/// @returns An output object containing the validation result.
json schema_validate_Maximum(json jInstance, json jMaximum)
{
    json joOutput = schema_output_GetMinimalObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_number>"));

    if (JsonGetFloat(jInstance) > JsonGetFloat(jMaximum))
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_maximum>"));
    else
        return schema_output_InsertAnnotation(joOutput, "maximum", jMaximum);
}

/// @brief Validates the number "exclusiveMaximum" keyword.
/// @param jInstance The instance to validate.
/// @param jExclusiveMaximum The schema value for "exclusiveMaximum".
/// @returns An output object containing the validation result.
json schema_validate_ExclusiveMaximum(json jInstance, json jExclusiveMaximum)
{
    json joOutput = schema_output_GetMinimalObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_number>"));

    if (JsonGetFloat(jInstance) >= JsonGetFloat(jExclusiveMaximum))
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_exclusivemaximum>"));
    else
        return schema_output_InsertAnnotation(joOutput, "exclusiveMaximum", jExclusiveMaximum);
}

/// @brief Validates the number "multipleOf" keyword.
/// @param jInstance The instance to validate.
/// @param jMultipleOf The schema value for "multipleOf".
/// @returns An output object containing the validation result.
json schema_validate_MultipleOf(json jInstance, json jMultipleOf)
{
    json joOutput = schema_output_GetMinimalObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_number>"));

    float fMultipleOf = JsonGetFloat(jMultipleOf);
    float fMultiple = JsonGetFloat(jInstance) / fMultipleOf;
    if (fabs(fMultiple - IntToFloat(FloatToInt(fMultiple))) < 0.00001)
        return schema_output_InsertAnnotation(joOutput, "multipleOf", jMultipleOf);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_multipleof>"));
}

/// @brief Validates the array "minItems" keyword.
/// @param jInstance The instance to validate.
/// @param jiMinItems The schema value for "minItems".
/// @returns An output object containing the validation result.
json schema_validate_MinItems(json jInstance, json jiMinItems)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_array>"));

    int nMinItems = JsonGetInt(jiMinItems);
    if (JsonGetLength(jInstance) >= nMinItems)
        return schema_output_InsertAnnotation(joOutput, "minItems", jiMinItems);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_minitems>"));
}

/// @brief Validates the array "maxItems" keyword.
/// @param jInstance The instance to validate.
/// @param jiMaxItems The schema value for "maxItems".
/// @returns An output object containing the validation result.
json schema_validate_MaxItems(json jInstance, json jiMaxItems)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_array>"));

    int nMaxItems = JsonGetInt(jiMaxItems);
    if (JsonGetLength(jInstance) <= nMaxItems)
        return schema_output_InsertAnnotation(joOutput, "maxItems", jiMaxItems);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_maxitems>"));
}

/// @brief Validates the array "uniqueItems" keyword.
/// @param jInstance The instance to validate.
/// @param jUniqueItems The schema value for "uniqueItems".
/// @returns An output object containing the validation result.
json schema_validate_UniqueItems(json jInstance, json jUniqueItems)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_array>"));

    if (!JsonGetInt(jUniqueItems))
        return joOutput;

    if (JsonGetLength(jInstance) == JsonGetLength(JsonArrayTransform(jInstance, JSON_ARRAY_UNIQUE)))
        return schema_output_InsertAnnotation(joOutput, "uniqueItems", jUniqueItems);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_uniqueitems>"));
}

/// @brief Validates interdependent array keywords "prefixItems", "items", "contains",
///     "minContains", "maxContains", "unevaluatedItems".
/// @param jaInstance The array instance to validate.
/// @param jaPrefixItems The schema value for "prefixItems".
/// @param joItems The schema value for "items"
/// @param joContains The schema value for "contains".
/// @param jiMinContains The schema value for "minContains".
/// @param jiMaxContains The schema value for "maxContains".
/// @param joUnevaluatedItems The schema value for "unevaluatedItems".
/// @returns An output object containing the validation result.
json schema_validate_Array(
    json jaInstance,
    json jaPrefixItems,
    json joItems,
    json joContains,
    json jiMinContains,
    json jiMaxContains,
    json joUnevaluatedItems
)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_array>"));

    int nInstanceLength = JsonGetLength(jaInstance);
    int nPrefixItemsLength = JsonGetType(jaPrefixItems) == JSON_TYPE_ARRAY ? JsonGetLength(jaPrefixItems) : 0;
    json jaEvaluatedIndices = JsonArray();

    // prefixItems
    if (nPrefixItemsLength > 0)
    {
        int i; for (; i < nPrefixItemsLength && i < nInstanceLength; i++)
        {
            json jItem = JsonArrayGet(jaInstance, i);
            json joPrefixItem = JsonArrayGet(jaPrefixItems, i);

            json jResult = schema_core_Validate(jItem, joPrefixItem);

            if (schema_output_GetValid(jResult))
            {
                joOutput = schema_output_InsertAnnotation(
                    joOutput,
                    "prefixItems",
                    JsonInt(i)
                );
            }
            else
            {
                joOutput = schema_output_InsertError(
                    joOutput,
                    JsonGetString(jResult) //, "error")
                );
                joOutput = schema_output_SetValid(joOutput, FALSE);
            }

            jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonInt(i));
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "prefixItems", jaPrefixItems);
    }

    // items
    if (JsonGetType(joItems) == JSON_TYPE_OBJECT || JsonGetType(joItems) == JSON_TYPE_BOOL)
    {
        int i; for (i = nPrefixItemsLength; i < nInstanceLength; i++)
        {
            json jItem = JsonArrayGet(jaInstance, i);
            json jResult = schema_core_Validate(jItem, joItems);

            if (schema_output_GetValid(jResult))
            {
                joOutput = schema_output_InsertAnnotation(
                    joOutput,
                    "items",
                    JsonInt(i)
                );
            }
            else
            {
                joOutput = schema_output_InsertError(
                    joOutput,
                    JsonGetString(jResult) //, "error")
                );
                joOutput = schema_output_SetValid(joOutput, FALSE);
            }

            jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonInt(i));
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "items", joItems);
    }

    // contains (+minContains, maxContains)
    json jaContainsMatched = JsonArray();
    int bContainsUsed = JsonGetType(joContains) == JSON_TYPE_OBJECT || JsonGetType(joContains) == JSON_TYPE_BOOL;
    if (bContainsUsed)
    {
        int nMatches = 0;
        int i; for (i = 0; i < nInstanceLength; i++)
        {
            json jItem = JsonArrayGet(jaInstance, i);
            json jResult = schema_core_Validate(jItem, joContains);
            if (schema_output_GetValid(jResult))
            {
                jaContainsMatched = JsonArrayInsert(jaContainsMatched, JsonInt(i));
                nMatches++;
            }
        }
        int nMin = JsonGetType(jiMinContains) == JSON_TYPE_INTEGER ? JsonGetInt(jiMinContains) : 1;
        int nMax = JsonGetType(jiMaxContains) == JSON_TYPE_INTEGER ? JsonGetInt(jiMaxContains) : 0x7FFFFFFF;

        if (nMatches < nMin)
            return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_mincontains>"));
        if (nMatches > nMax)
            return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_maxcontains>"));
        joOutput = schema_output_InsertAnnotation(joOutput, "contains", joContains);
        if (JsonGetType(jiMinContains) == JSON_TYPE_INTEGER)
            joOutput = schema_output_InsertAnnotation(joOutput, "minContains", jiMinContains);
        if (JsonGetType(jiMaxContains) == JSON_TYPE_INTEGER)
            joOutput = schema_output_InsertAnnotation(joOutput, "maxContains", jiMaxContains);
        for (i = 0; i < JsonGetLength(jaContainsMatched); i++)
            jaEvaluatedIndices = JsonArrayInsert(jaEvaluatedIndices, JsonArrayGet(jaContainsMatched, i));
    }

    // unevaluatedItems
    if (JsonGetType(joUnevaluatedItems) == JSON_TYPE_OBJECT || JsonGetType(joUnevaluatedItems) == JSON_TYPE_BOOL)
    {
        json joEvalMap = JsonObject();
        int i; for (; i < JsonGetLength(jaEvaluatedIndices); i++)
            joEvalMap = JsonObjectSet(joEvalMap, IntToString(JsonGetInt(JsonArrayGet(jaEvaluatedIndices, i))), JSON_TRUE);
        
        for (i = 0; i < nInstanceLength; i++)
        {
            if (!schema_HasKey(joEvalMap, IntToString(i)))
            {
                json jItem = JsonArrayGet(jaInstance, i);
                json jResult = schema_core_Validate(jItem, joUnevaluatedItems);

                if (schema_output_GetValid(jResult))
                {
                    joOutput = schema_output_InsertAnnotation(
                        joOutput,
                        "unevaluatedItems",
                        JsonInt(i)
                    );
                }
                else
                {
                    joOutput = schema_output_InsertError(
                        joOutput,
                        JsonGetString(jResult) //, "error")
                    );
                    joOutput = schema_output_SetValid(joOutput, FALSE);
                }
            }
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "unevaluatedItems", joUnevaluatedItems);
    }

    return joOutput;
}

/// @brief Validates the object "required" keyword.
/// @param joInstance The object instance to validate.
/// @param jaRequired The schema value for "required".
/// @returns An output object containing the validation result.
json schema_validate_Required(json joInstance, json jaRequired)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_object>"));

    json jaMissing = JsonArray();
    int nRequiredLength = JsonGetLength(jaRequired);
    int i; for (; i < nRequiredLength; i++)
    {
        string sProperty = JsonGetString(JsonArrayGet(jaRequired, i));
        if (JsonFind(joInstance, JsonString(sProperty)) == JsonNull())
            jaMissing = JsonArrayInsert(jaMissing, JsonString(sProperty));
    }

    if (JsonGetLength(jaMissing) > 0)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_required>"));
    else
        return schema_output_InsertAnnotation(joOutput, "required", jaRequired);
}

/// @brief Validates the object "minProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jiMinProperties The schema value for "minProperties".
/// @returns An output object containing the validation result.
json schema_validate_MinProperties(json joInstance, json jiMinProperties)
{
    json joOutput = schema_output_GetMinimalObject();
    
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_object>"));
    
    if (JsonGetLength(joInstance) < JsonGetInt(jiMinProperties))
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_minproperties>"));
    else
        return schema_output_InsertAnnotation(joOutput, "minProperties", jiMinProperties);
}

/// @brief Validates the object "maxProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jiMaxProperties The schema value for "maxProperties".
/// @returns An output object containing the validation result.
json schema_validate_MaxProperties(json joInstance, json jiMaxProperties)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_object>"));

    if (JsonGetLength(joInstance) > JsonGetInt(jiMaxProperties))
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_maxproperties>"));
    else
        return schema_output_InsertAnnotation(joOutput, "maxProperties", jiMaxProperties);
}

/// @brief Validates the object "dependentRequired" keyword.
/// @param joInstance The object instance to validate.
/// @param joDependentRequired The schema value for "dependentRequired".
/// @returns An output object containing the validation result.
json schema_validate_DependentRequired(json joInstance, json joDependentRequired)
{
    json joOutput = schema_output_GetMinimalObject();
    
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_object>"));

    json jaPropertyKeys = JsonObjectKeys(joDependentRequired);
    int i; for (; i < JsonGetLength(joDependentRequired); i++)
    {
        string sPropertyKey = JsonGetString(JsonArrayGet(jaPropertyKeys, i));
        if (JsonFind(joInstance, JsonArrayGet(jaPropertyKeys, i)) != JsonNull())
        {
            json jaDependencies = JsonObjectGet(joDependentRequired, sPropertyKey);
            int i; for (; i < JsonGetLength(jaDependencies); i++)
            {
                string sProperty = JsonGetString(JsonArrayGet(jaDependencies, i));
                if (JsonFind(joInstance, JsonArrayGet(jaDependencies, i)) == JsonNull())
                    joOutput = schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_dependentrequired>"));
            }
        }
    }

    json jaErrors = JsonObjectGet(joOutput, "errors");
    if (JsonGetType(jaErrors) == JSON_TYPE_NULL || JsonGetLength(jaErrors) == 0)
        joOutput = schema_output_InsertAnnotation(joOutput, "dependentRequired", joDependentRequired);

    return joOutput;
}

/// @brief Validates interdependent object keywords "properties", "patternProperties",
///     "additionalProperties", "dependentSchemas", "propertyNames", "unevaluatedProperties".
/// @param joInstance The object instance to validate.
/// @param joProperties The schema value for "properties".
/// @param joPatternProperties The schema value for "patternProperties".
/// @param joAdditionalProperties The schema value for "additionalProperties".
/// @param joDependentSchemas The schema value for "dependentSchemas".
/// @param joPropertyNames The schema value for "propertyNames".
/// @param joUnevaluatedProperties The schema value for "unevaluatedProperties".
/// @returns An output object containing the validation result.
json schema_validate_Object(
    json joInstance,
    json joProperties,
    json joPatternProperties,
    json joAdditionalProperties,
    json joDependentSchemas,
    json joPropertyNames,
    json joUnevaluatedProperties
)
{
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<instance_object>"));

    json joEvaluated = JsonObject(); // Track evaluated properties by name
    json jaInstanceKeys = JsonObjectKeys(joInstance);

    // 1. properties
    if (JsonGetType(joProperties) == JSON_TYPE_OBJECT)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string sKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(joProperties, JsonString(sKey)) != JsonNull())
            {
                joEvaluated = JsonObjectSet(joEvaluated, sKey, JSON_TRUE);
                json joPropSchema = JsonObjectGet(joProperties, sKey);
                json joResult = schema_core_Validate(JsonObjectGet(joInstance, sKey), joPropSchema);
                
                if (schema_output_GetValid(joResult))
                    joOutput = schema_output_InsertAnnotation(joOutput, "properties", JsonString(sKey));
                else
                    joOutput = schema_output_InsertError(joOutput, "property '" + sKey + "': " + JsonGetString(joResult) /*, "error") */);
            }/// @todo fix all these JsonGetString(joResult, "error") issues.  What are they supposed to be?
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "properties", joProperties);
    }

    // 2. patternProperties
    if (JsonGetType(joPatternProperties) == JSON_TYPE_OBJECT)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        json jaPatternKeys = JsonObjectKeys(joPatternProperties);
        int j, nPatterns = JsonGetLength(jaPatternKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            for (j = 0; j < nPatterns; ++j)
            {
                string pattern = JsonGetString(JsonArrayGet(jaPatternKeys, j));
                if (RegExpMatch(pattern, key) != JsonArray())
                {
                    joEvaluated = JsonObjectSet(joEvaluated, key, JSON_TRUE);
                    json joPatSchema = JsonObjectGet(joPatternProperties, pattern);
                    json joResult = schema_core_Validate(JsonObjectGet(joInstance, key), joPatSchema);
                    if (schema_output_GetValid(joResult))
                        joOutput = schema_output_InsertAnnotation(joOutput, "patternProperties", JsonString(key));
                    else
                        joOutput = schema_output_InsertError(joOutput, "pattern property '" + key + "' (pattern: " + pattern + "): " + JsonGetString(joResult) /*, "error")*/);
                }
            }
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "patternProperties", joPatternProperties);
    }

    // 3. additionalProperties
    // Only applies to properties not matched by properties or patternProperties
    if (JsonGetType(joAdditionalProperties) == JSON_TYPE_OBJECT || JsonGetType(joAdditionalProperties) == JSON_TYPE_BOOL)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(joEvaluated, JsonString(key)) == JsonNull())
            {
                if (JsonGetType(joAdditionalProperties) == JSON_TYPE_BOOL && !JsonGetInt(joAdditionalProperties))
                    joOutput = schema_output_InsertError(joOutput, "additional property '" + key + "' is not allowed");
                else if (JsonGetType(joAdditionalProperties) == JSON_TYPE_OBJECT)
                {
                    json joResult = schema_core_Validate(JsonObjectGet(joInstance, key), joAdditionalProperties);
                    if (schema_output_GetValid(joResult))
                        joOutput = schema_output_InsertAnnotation(joOutput, "additionalProperties", JsonString(key));
                    else
                        joOutput = schema_output_InsertError(joOutput, "additional property '" + key + "': " + JsonGetString(joResult) /*, "error")*/);
                }
                joEvaluated = JsonObjectSet(joEvaluated, key, JSON_TRUE);
            }
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "additionalProperties", joAdditionalProperties);
    }

    // 4. dependentSchemas
    if (JsonGetType(joDependentSchemas) == JSON_TYPE_OBJECT)
    {
        json jaDepKeys = JsonObjectKeys(joDependentSchemas);
        int i, nDeps = JsonGetLength(jaDepKeys);
        for (i = 0; i < nDeps; ++i)
        {
            string depKey = JsonGetString(JsonArrayGet(jaDepKeys, i));
            if (JsonFind(joInstance, JsonString(depKey)) != JsonNull())
            {
                joEvaluated = JsonObjectSet(joEvaluated, depKey, JSON_TRUE);
                json joDepSchema = JsonObjectGet(joDependentSchemas, depKey);
                json joResult = schema_core_Validate(joInstance, joDepSchema);
                if (schema_output_GetValid(joResult))
                    joOutput = schema_output_InsertAnnotation(joOutput, "dependentSchemas", JsonString(depKey));
                else
                    joOutput = schema_output_InsertError(joOutput, "dependent schema for property '" + depKey + "': " + JsonGetString(joResult) /*, "error")*/);
            }
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "dependentSchemas", joDependentSchemas);
    }

    // 5. propertyNames
    if (JsonGetType(joPropertyNames) == JSON_TYPE_OBJECT || JsonGetType(joPropertyNames) == JSON_TYPE_BOOL)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            json joResult = schema_core_Validate(JsonString(key), joPropertyNames);
            if (schema_output_GetValid(joResult))
                joOutput = schema_output_InsertAnnotation(joOutput, "propertyNames", JsonString(key));
            else
                joOutput = schema_output_InsertError(joOutput, "property name '" + key + "' is invalid: " + JsonGetString(joResult) /*, "error")*/);
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "propertyNames", joPropertyNames);
    }

    // 6. unevaluatedProperties
    if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_OBJECT || JsonGetType(joUnevaluatedProperties) == JSON_TYPE_BOOL)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(joEvaluated, JsonString(key)) == JsonNull())
            {
                if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_BOOL && !JsonGetInt(joUnevaluatedProperties))
                    joOutput = schema_output_InsertError(joOutput, "unevaluated property '" + key + "' is not allowed");
                else if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_OBJECT)
                {
                    json joResult = schema_core_Validate(JsonObjectGet(joInstance, key), joUnevaluatedProperties);
                    if (schema_output_GetValid(joResult))
                        joOutput = schema_output_InsertAnnotation(joOutput, "unevaluatedProperties", JsonString(key));
                    else
                        joOutput = schema_output_InsertError(joOutput, "unevaluated property '" + key + "': " + JsonGetString(joResult) /*, "error")*/);
                }
            }
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "unevaluatedProperties", joUnevaluatedProperties);
    }

    return joOutput;
}

/// @brief Validates the applicator "not" keyword
/// @param jInstance The instance to validate.
/// @param joNot The schema value for "not".
/// @returns An output object containing the validation result.
json schema_validate_Not(json jInstance, json joNot)
{
    json joOutput = schema_output_GetMinimalObject();

    if (schema_output_GetValid(schema_core_Validate(jInstance, joNot)))
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_not>"));
    else
        return schema_output_InsertAnnotation(joOutput, "not", joNot);
}

/// @brief Validates the applicator "allOf" keyword
/// @param jInstance The instance to validate.
/// @param jaAllOf The schema value for "allOf".
/// @returns An output object containing the validation result.
json schema_validate_AllOf(json jInstance, json jaAllOf)
{
    json joOutput = schema_output_GetMinimalObject();

    int i; for (; i < JsonGetLength(jaAllOf); i++)
    {
        if (!schema_output_GetValid(schema_core_Validate(jInstance, JsonArrayGet(jaAllOf, i))))
            return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_allof>"));
    }

    return schema_output_InsertAnnotation(joOutput, "allOf", jaAllOf);
}

/// @brief Validates the applicator "anyOf" keyword
/// @param jInstance The instance to validate.
/// @param jaAnyOf The schema value for "anyOf".
/// @returns An output object containing the validation result.
json schema_validate_AnyOf(json jInstance, json jaAnyOf)
{
    json joOutput = schema_output_GetMinimalObject();

    int i; for (; i < JsonGetLength(jaAnyOf); i++)
    {
        if (schema_output_GetValid(schema_core_Validate(jInstance, JsonArrayGet(jaAnyOf, i))))
            return schema_output_InsertAnnotation(joOutput, "anyOf", jaAnyOf);
    }

    return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_anyof>"));
}

/// @brief Validates the applicator "oneOf" keyword
/// @param jInstance The instance to validate.
/// @param jaOneOf The schema value for "oneOf".
/// @returns An output object containing the validation result.
json schema_validate_OneOf(json jInstance, json jaOneOf)
{
    json joOutput = schema_output_GetMinimalObject();

    int nMatches;
    int i; nMatches = 0;
    for (i = 0; i < JsonGetLength(jaOneOf); i++)
    {
        if (schema_output_GetValid(schema_core_Validate(jInstance, JsonArrayGet(jaOneOf, i))))
        {
            if (++nMatches > 1)
                break;
        }
    }

    if (nMatches == 1)
        return schema_output_InsertAnnotation(joOutput, "oneOf", jaOneOf);
    else
        return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_oneof>"));
}

/// @brief Validates interdependent applicator keywords "if", "then", "else".
/// @param joInstance The object instance to validate.
/// @param joIf The schema value for "if".
/// @param joThen The schema value for "then".
/// @param joElse The schema value for "else".
/// @returns An output object containing the validation result.
json schema_validate_If(json jInstance, json joIf, json joThen, json joElse)
{
    json joOutput = schema_output_GetMinimalObject();

    if (schema_output_GetValid(schema_core_Validate(jInstance, joIf)))
    {
        if (JsonGetType(joThen) != JSON_TYPE_NULL)
        {
            if (!schema_output_GetValid(schema_core_Validate(jInstance, joThen)))
                return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_then>"));
        }
    }
    else
    {
        if (JsonGetType(joElse) != JSON_TYPE_NULL)
        {
            if (!schema_output_GetValid(schema_core_Validate(jInstance, joElse)))
                return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_then>"));
        }
    }

    joOutput = schema_output_InsertAnnotation(joOutput, "if", joIf);
    if (JsonGetType(joThen) != JSON_TYPE_NULL)
        joOutput = schema_output_InsertAnnotation(joOutput, "then", joThen);
    if (JsonGetType(joElse) != JSON_TYPE_NULL)
        joOutput = schema_output_InsertAnnotation(joOutput, "else", joElse);

    return joOutput;
}

/// @brief Annotates the output with a metadata keyword.
/// @param sKey The metadata keyword.
/// @param jValue The value for the metadata keyword.
/// @returns An output object containing the annotation.
json schema_validate_Metadata(string sKey, json jValue)
{
    return schema_output_InsertAnnotation(schema_output_GetMinimalObject(), sKey, jValue);
}

json schema_core_Validate(json jInstance, json joSchema)
{
    json joResult = JSON_NULL;
    json joOutput = schema_output_GetMinimalObject();

    if (JsonGetType(joSchema) == JSON_TYPE_BOOL)
    {
        if (JsonGetInt(joSchema) == TRUE)
            return schema_output_InsertAnnotation(joOutput, "valid", JSON_TRUE);
        else
            return schema_output_InsertError(joOutput, schema_output_GetErrorMessage("<validate_never>"));
    }

    if (joSchema == JsonObject())
        return schema_output_InsertAnnotation(joOutput, "valid", JSON_TRUE);

    int bHandledConditional = FALSE;
    int bHandledArray = FALSE;
    int bHandledObject = FALSE;

    json jaKeys = JsonObjectKeys(joSchema);
    int i; for (; i < JsonGetLength(jaKeys); i++)
    {
        string sKey = JsonGetString(JsonArrayGet(jaKeys, i));
        
        // Conditional keywords group
        if (sKey == "if" || sKey == "then" || sKey == "else")
        {
            if (!bHandledConditional)
            {
                joResult = schema_validate_If(jInstance,
                    JsonObjectGet(joSchema, "if"),
                    JsonObjectGet(joSchema, "then"),
                    JsonObjectGet(joSchema, "else")
                );

                bHandledConditional = TRUE;
            }
            continue;
        }

        // Array keywords group
        if (sKey == "prefixItems" || sKey == "items" || sKey == "contains" ||
            sKey == "minContains" || sKey == "maxContains" || sKey == "unevaluatedItems")
        {
            if (!bHandledArray)
            {
                joResult = schema_validate_Array(jInstance,
                    JsonObjectGet(joSchema, "prefixItems"),
                    JsonObjectGet(joSchema, "items"),
                    JsonObjectGet(joSchema, "contains"),
                    JsonObjectGet(joSchema, "minContains"),
                    JsonObjectGet(joSchema, "maxContains"),
                    JsonObjectGet(joSchema, "unevaluatedItems")
                );

                bHandledArray = TRUE;
            }
            continue;
        }

        // Object keywords group
        if (sKey == "properties" || sKey == "patternProperties" ||
            sKey == "additionalProperties" || sKey == "dependentSchemas" ||
            sKey == "propertyNames" || sKey == "unevaluatedProperties")
        {
            if (!bHandledObject)
            {
                joResult = schema_validate_Object(jInstance,
                    JsonObjectGet(joSchema, "properties"),
                    JsonObjectGet(joSchema, "patternProperties"),
                    JsonObjectGet(joSchema, "additionalProperties"),
                    JsonObjectGet(joSchema, "dependentSchemas"),
                    JsonObjectGet(joSchema, "propertyNames"),
                    JsonObjectGet(joSchema, "unevaluatedProperties")
                );

                bHandledObject = TRUE;
            }
            continue;
        }

        // Metadata keywords: always call for each occurrence
        if (sKey == "title" || sKey == "description" || sKey == "default" ||
            sKey == "deprecated" || sKey == "readOnly" || sKey == "writeOnly" ||
            sKey == "examples")
        {
            joResult = schema_validate_Metadata(sKey, JsonObjectGet(joSchema, sKey));
            continue;
        }

        // Individual keyword dispatchers
        if (sKey == "allOf")            { joResult = schema_validate_AllOf(jInstance, joSchema); continue; }
        if (sKey == "anyOf")            { joResult = schema_validate_AnyOf(jInstance, joSchema); continue; }
        if (sKey == "oneOf")            { joResult = schema_validate_OneOf(jInstance, joSchema); continue; }
        if (sKey == "not")              { joResult = schema_validate_Not(jInstance, joSchema); continue; }
        if (sKey == "required")         { joResult = schema_validate_Required(jInstance, joSchema); continue; }
        if (sKey == "minProperties")    { joResult = schema_validate_MinProperties(jInstance, joSchema); continue; }
        if (sKey == "maxProperties")    { joResult = schema_validate_MaxProperties(jInstance, joSchema); continue; }
        if (sKey == "dependentRequired"){ joResult = schema_validate_DependentRequired(jInstance, joSchema); continue; }
        if (sKey == "type")             { joResult = schema_validate_Type(jInstance, joSchema); continue; }
        if (sKey == "enum")             { joResult = schema_validate_Enum(jInstance, joSchema); continue; }
        if (sKey == "const")            { joResult = schema_validate_Const(jInstance, joSchema); continue; }
        if (sKey == "multipleOf")       { joResult = schema_validate_MultipleOf(jInstance, joSchema); continue; }
        if (sKey == "maximum")          { joResult = schema_validate_Maximum(jInstance, joSchema); continue; }
        if (sKey == "exclusiveMaximum") { joResult = schema_validate_ExclusiveMaximum(jInstance, joSchema); continue; }
        if (sKey == "minimum")          { joResult = schema_validate_Minimum(jInstance, joSchema); continue; }
        if (sKey == "exclusiveMinimum") { joResult = schema_validate_ExclusiveMinimum(jInstance, joSchema); continue; }
        if (sKey == "maxLength")        { joResult = schema_validate_MaxLength(jInstance, joSchema); continue; }
        if (sKey == "minLength")        { joResult = schema_validate_MinLength(jInstance, joSchema); continue; }
        if (sKey == "pattern")          { joResult = schema_validate_Pattern(jInstance, joSchema); continue; }
        if (sKey == "maxItems")         { joResult = schema_validate_MaxItems(jInstance, joSchema); continue; }
        if (sKey == "minItems")         { joResult = schema_validate_MinItems(jInstance, joSchema); continue; }
        if (sKey == "uniqueItems")      { joResult = schema_validate_UniqueItems(jInstance, joSchema); continue; }
        if (sKey == "format")           { joResult = schema_validate_Format(jInstance, joSchema); continue; }

        // ...handle any additional keywords as needed...
    }

    return joResult;
}

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
    return 0; // stub
}
