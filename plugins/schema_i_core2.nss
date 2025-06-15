
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

    return jPath;
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

const string SCHEMA_OUTPUT_VERBOSE = "verbose";
const string SCHEMA_OUTPUT_DETAILED = "detailed";
const string SCHEMA_OUTPUT_BASIC = "basic";
const string SCHEMA_OUTPUT_FLAG = "flag";

json schema_output_Set(json joOutput, string sKey, json jValue)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT || sKey == "" || JsonGetType(jValue) == JSON_TYPE_NULL)
        return joOutput;

    return JsonObjectSet(joOutput, sKey, jValue);
}

int schema_ouput_GetValid(json joOutput)
{
    return (JsonObjectGet(joOutput, "valid") == JSON_TRUE);
}

json schema_output_SetValid(json joOutput, int bValid = TRUE)
{
    return JsonObjectSet(joOutput, "valid", bValid ? JSON_TRUE : JSON_FALSE);
}

json schema_output_SetProperty(json joOutput, string sKey, json jValue)
{
    return JsonObjectSet(joOutput, sKey, jValue);
}

json schema_output_SetError(json joOutput, string sError)
{
    if (sError == "")
        return joOutput;

    return JsonObjectSet(schema_output_SetValid(joOutput, FALSE), "error", JsonString(sError));
}

json schema_output_InsertError(json joOutput, string sError)
{
    if (sError == "")
        return joOutput;

    json jaErrors = JsonObjectGet(joOutput, "errors");
    if (JsonGetType(jaErrors) == JSON_TYPE_NULL)
        jaErrors = JsonArray();

    jaErrors = JsonArrayInsert(jaErrors, schema_output_SetError(schema_output_GetOutputObject(), sError));
    return schema_output_SetValid(JsonObjectSet(joOutput, "errors", jaErrors), FALSE);
}

json schema_output_InsertAnnotation(json joOutput, string sKey, json jValue)
{
    if (JsonGetType(joAnnotation) != JSON_TYPE_OBJECT)
        return joOutput;

    json jaAnnotations = JsonObjectGet(joOutput, "annotations");
    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL)
        jaAnnotations = JsonArray();

    json joAnnotation = schema_output_SetProperty(schema_output_GetOutputObject(), sKey, jValue);
    return JsonObjectSet(joOutput, "annotations", JsonArrayInsert(jaAnnotations, joAnnotation));
}

json schema_output_GetOutputObject(string sVerbosity = SCHEMA_OUTPUT_VERBOSE)
{
    string s = r"
        WITH RECURSIVE
            matching_index AS (
                SELECT
                    json_each.key AS idx
                FROM
                    json_each(json_extract(@schema, '$.anyOf'))
                WHERE
                    -- Look for a $ref to the desired output level in $defs
                    json_extract(json_each.value, '$.$ref') = '#/$defs/' || @output_level
            ),
            chosen_def AS (
                SELECT
                    '$."$defs".' || @output_level AS def_path
            ),
            chosen_ref AS (
                SELECT
                    json_extract(@schema, def_path || '.$ref') AS ref,
                    def_path
                FROM
                    chosen_def
            ),
            resolved_path AS (
                SELECT
                    CASE
                        WHEN ref IS NOT NULL AND ref LIKE '#/$defs/%' THEN
                            '$."$defs".' || substr(ref, 10) -- resolves #/$defs/outputUnit to $."$defs".outputUnit
                        ELSE
                            def_path
                    END AS final_path
                FROM
                    chosen_ref
            ),
            required_fields AS (
                SELECT
                    value AS key
                FROM
                    resolved_path,
                    json_each(json_extract(@schema, final_path || '.required'))
            ),
            field_types AS (
                SELECT
                    rf.key,
                    json_extract(@schema, rp.final_path || '.properties.' || rf.key || '.type') AS type
                FROM
                    required_fields rf, resolved_path rp
            ),
            min_obj AS (
                SELECT
                    '{' || group_concat(
                        '"' || key || '":' ||
                        CASE type
                            WHEN 'boolean' THEN true
                            WHEN 'integer' THEN 0
                            WHEN 'number' THEN 0
                            WHEN 'string' THEN json_quote('')
                            WHEN 'array' THEN json_array()
                            WHEN 'object' THEN json_object()
                            ELSE null
                        END
                    , ',') || '}' AS result
                FROM
                    field_types
            )
        SELECT result FROM min_obj;
    ";

    sqlquery q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindString(q, ":output_level", sVerbosity);
    SqlBindJson(q, ":schema", JsonParse(ResManGetFileContents("output", RESTYPE_TXT)));
    
    return SqlStep(q) ? SqlGetJson(q, 0) : JsonObject();
}

/// @todo this should be a convenience function to turn schema_output_Flag into an easily
///     accessible boolean value.  Move this out of this section and into the main
///     function area.
int schema_output_Valid(json joOutput)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT)
        return FALSE;

    if (JsonFind(joOutput, JsonString("valid")) == JsonNull())
        return FALSE;

    return JsonGetInt(JsonObjectGet(joOutput, "valid"));
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
    json joOutput = schema_output_GetOutputObject();

    int nInstanceType = JsonGetType(jInstance);
    if (JsonGetType(jType) == JSON_TYPE_STRING)
    {
        if (JsonGetString(jType) == "number")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
                joOutput = schema_output_InsertAnnotation(joOutput, "type", jType);
        }
        else
        {
            json jaTypes = JsonParse(r"
                ""null"",
                ""object"",
                ""array"",
                ""string"",
                ""integer"",
                ""float"",
                ""boolean""
            ");
            json jiFind = JsonFind(jaTypes, jType);
            if (JsonGetType(jiFind) != JSON_TYPE_NULL && JsonGetInt(jiFind) == nInstanceType)
                joOutput = schema_output_InsertAnnotation(joOutput, "type", jType);
        }
    }
    else if (JsonGetType(jType) == JSON_TYPE_ARRAY)
    {
        int i; for (; i < JsonGetLength(jType); i++)
        {
            json joValidate = schema_validate_Type(jInstance, JsonArrayGet(jType, i));
            if (schema_ouput_GetValid(joValidate))
                return joValidate;
        }
    }

    json jaAnnotations = JsonObjectGet(joOutput, "annotations");
    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL || JsonGetLength(jaAnnotations) == 0)
        return schema_output_SetError(schema_output_SetValid(joOutput, FALSE), "instance does not match type");

    return joOutput;
}

/// @brief Validates the global "enum" and "const" keywords.
/// @param jInstance The instance to validate.
/// @param jaEnum The array of valid elements for enum/const. Assumed to be validated against the metaschema.
/// @returns An output object containing the validation result.
/// @note Due to NWN's nlohmann::json implementation, JsonFind() conducts a
///     deep comparison of the instance and enum/const values; separate handling
///     for the various json types is not required.
json schema_validate_enum(json jInstance, json jaEnum, string sDescriptor = "enum")
{
    json joOutput = schema_output_GetOutputObject();

    json jiIndex = JsonFind(jaEnum, jInstance);
    if (JsonGetType(jiIndex) == JSON_TYPE_NULL)
        return schema_output_SetError(joOutput, "instance not found in " + sDescriptor);
    else
        return schema_output_InsertAnnotation(joOutput, sDescriptor, JsonArrayGet(jaEnum, JsonGetInt(jiIndex)));
}

/// @brief Validates the global "enum" keyword.
/// @param jInstance The instance to validate.
/// @param jaEnum The schema value for "enum".
/// @returns An output object containing the validation result.
json schema_validate_Enum(json jInstance, json jaEnum, string sEnum)
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
    json joOutput = schema_output_GetOutputObject();
    
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_SetError(joOutput, "instance must be a string");

    int nMinLength = JsonGetInt(jiMinLength);
    if (GetStringLength(JsonGetString(jsInstance)) >= nMinLength)
        return schema_output_InsertAnnotation(joOutput, "minLength", jiMinLength);
    else
        return schema_output_SetError(joOutput, "instance is shorter than minLength");
}

/// @brief Validates the string "maxLength" keyword.
/// @param jsInstance The instance to validate (assumed to be a string).
/// @param jiMaxLength The schema value for "maxLength" (assumed to be a non-negative integer).
/// @returns An output object containing the validation result.
json schema_validate_MaxLength(json jsInstance, json jiMaxLength)
{
    json joOutput = schema_output_GetOutputObject();
    
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_SetError(joOutput, "instance must be a string");

    int nMaxLength = JsonGetInt(jiMaxLength);
    if (GetStringLength(JsonGetString(jsInstance)) <= nMaxLength)
        return schema_output_InsertAnnotation(joOutput, "maxLength", jiMaxLength);
    else
        return schema_output_SetError(joOutput, "instance is longer than maxLength");
}

/// @brief Validates the string "pattern" keyword.
/// @param jsInstance The instance to validate.
/// @param jsPattern The schema value for "pattern".
/// @returns An output object containing the validation result.
json schema_validate_Pattern(json jsInstance, json jsPattern)
{
    json joOutput = schema_output_GetOutputObject();
    
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
        return schema_output_SetError(joOutput, "instance must be a string");

    if (RegExpMatch(JsonGetString(jsPattern), JsonGetString(jsInstance)) != JsonArray())
        return schema_output_InsertAnnotation(joOutput, "pattern", jsPattern);
    else
        return schema_output_SetError(joOutput, "instance does not match pattern");
}
    
/// @brief Validates the string "format" keyword.
/// @param jInstance The instance to validate.
/// @param jFormat The schema value for "format" (a string).
/// @returns An output object containing the validation result.
json schema_validate_Format(json jInstance, json jFormat)
{
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(jInstance) != JSON_TYPE_STRING)
        return schema_output_SetError(joOutput, "instance must be a string to validate format");

    if (JsonGetType(jFormat) != JSON_TYPE_STRING)
        return schema_output_SetError(joOutput, "format constraint must be a string");

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
        bValid = RegExpMatch("^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\."
                             "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\."
                             "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\."
                             "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$", sInstance) != JsonArray();
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
        return schema_output_SetError(joOutput, "unsupported format: " + sFormat);
    }

    if (bValid)
        joOutput = schema_output_InsertAnnotation(joOutput, "format", jFormat);
    else
        return schema_output_SetError(schema_output_SetValid(joOutput, FALSE), "instance does not match format: " + sFormat);

    return joOutput;
}

/// @brief Validates the number "minimum" keyword.
/// @param jInstance The instance to validate (assumed to be a number).
/// @param jMinimum The schema value for "minimum" (assumed to be a number).
/// @returns An output object containing the validation result.
json schema_validate_Minimum(json jInstance, json jMinimum)
{
    json joOutput = schema_output_GetOutputObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_SetError(joOutput, "instance must be a number");

    if (JsonGetFloat(jInstance) < JsonGetFloat(jMinimum))
        return schema_output_SetError(joOutput, "instance is less than minimum");
    else
        return schema_output_InsertAnnotation(joOutput, "minimum", jMinimum);
}

/// @brief Validates the number "exclusiveMinimum" keyword.
/// @param jInstance The instance to validate.
/// @param jExclusiveMinimum The schema value for "exclusiveMinimum".
/// @returns An output object containing the validation result.
json schema_validate_ExclusiveMinimum(json jInstance, json jExclusiveMinimum)
{
    json joOutput = schema_output_GetOutputObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_SetError(joOutput, "instance must be a number");

    if (JsonGetFloat(jInstance) <= JsonGetFloat(jExclusiveMinimum))
        return schema_output_SetError(joOutput, "instance is not greater than exclusiveMinimum");
    else
        return schema_output_InsertAnnotation(joOutput, "exclusiveMinimum", jExclusiveMinimum);
}

/// @brief Validates the number "maximum" keyword.
/// @param jInstance The instance to validate.
/// @param jMaximum The schema value for "maximum".
/// @returns An output object containing the validation result.
json schema_validate_Maximum(json jInstance, json jMaximum)
{
    json joOutput = schema_output_GetOutputObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_SetError(joOutput, "instance must be a number");

    if (JsonGetFloat(jInstance) > JsonGetFloat(jMaximum))
        return schema_output_SetError(joOutput, "instance is greater than maximum");
    else
        return schema_output_InsertAnnotation(joOutput, "maximum", jMaximum);
}

/// @brief Validates the number "exclusiveMaximum" keyword.
/// @param jInstance The instance to validate.
/// @param jExclusiveMaximum The schema value for "exclusiveMaximum".
/// @returns An output object containing the validation result.
json schema_validate_ExclusiveMaximum(json jInstance, json jExclusiveMaximum)
{
    json joOutput = schema_output_GetOutputObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_SetError(joOutput, "instance must be a number");

    if (JsonGetFloat(jInstance) >= JsonGetFloat(jExclusiveMaximum))
        return schema_output_SetError(joOutput, "instance is not less than exclusiveMaximum");
    else
        return schema_output_InsertAnnotation(joOutput, "exclusiveMaximum", jExclusiveMaximum);
}

/// @brief Validates the number "multipleOf" keyword.
/// @param jInstance The instance to validate.
/// @param jMultipleOf The schema value for "multipleOf".
/// @returns An output object containing the validation result.
json schema_validate_MultipleOf(json jInstance, json jMultipleOf)
{
    json joOutput = schema_output_GetOutputObject();

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
        return schema_output_SetError(joOutput, "instance must be a number");

    float fMultipleOf = JsonGetFloat(jMultipleOf);
    if (fMultipleOf <= 0.0)
        return schema_output_SetError(joOutput, "multipleOf must be greater than zero");

    float fMultiple = JsonGetFloat(jInstance) / fMultipleOf;
    if (fabs(fMultiple - IntToFloat(FloatToInt(fMultiple))) < 0.00001)
        return schema_output_InsertAnnotation(joOutput, "multipleOf", jMultipleOf);
    else
        return schema_output_SetError(joOutput, "instance is not a multiple of multipleOf");
}

/// @brief Validates the array "minItems" keyword.
/// @param jInstance The instance to validate.
/// @param jiMinItems The schema value for "minItems".
/// @returns An output object containing the validation result.
json schema_validate_MinItems(json jInstance, json jiMinItems)
{
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
        return schema_output_SetError(joOutput, "instance must be an array");

    int nMinItems = JsonGetInt(jiMinItems);
    if (JsonGetLength(jInstance) >= nMinItems)
        return schema_output_InsertAnnotation(joOutput, "minItems", jiMinItems);
    else
        return schema_output_SetError(joOutput, "array length is less than minItems");
}

/// @brief Validates the array "maxItems" keyword.
/// @param jInstance The instance to validate.
/// @param jiMaxItems The schema value for "maxItems".
/// @returns An output object containing the validation result.
json schema_validate_MaxItems(json jInstance, json jiMaxItems)
{
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
        return schema_output_SetError(joOutput, "instance must be an array");

    int nMaxItems = JsonGetInt(jiMaxItems);
    if (JsonGetLength(jInstance) <= nMaxItems)
        return schema_output_InsertAnnotation(joOutput, "maxItems", jiMaxItems);
    else
        return schema_output_SetError(joOutput, "array length is greater than maxItems");
}

/// @brief Validates the array "uniqueItems" keyword.
/// @param jInstance The instance to validate.
/// @param jUniqueItems The schema value for "uniqueItems".
/// @returns An output object containing the validation result.
json schema_validate_UniqueItems(json jInstance, json jUniqueItems)
{
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
        return schema_output_SetError(joOutput, "instance must be an array for uniqueItems validation");

    if (!JsonGetBool(jUniqueItems))
        return joOutput;

    if (JsonGetLength(jInstance) == JsonGetLength(JsonArrayTransform(jInstance, JSON_ARRAY_UNIQUE)))
        return schema_output_InsertAnnotation(joOutput, "uniqueItems", jUniqueItems);
    else
        return schema_output_SetError(joOutput, "array contains duplicate items");
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
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_SetError(joOutput, "instance must be an array");

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

            json jResult = schema_validate(jItem, joPrefixItem);

            if (JsonGetBool(jResult, "valid"))
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
                    JsonGetString(jResult, "error")
                );
                joOutput = schema_output_SetValid(joOutput, FALSE);
            }

            jaEvaluatedIndices = JsonArrayAdd(jaEvaluatedIndices, JsonInt(i));
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "prefixItems", jaPrefixItems);
    }

    // items
    if (JsonGetType(joItems) == JSON_TYPE_OBJECT || JsonGetType(joItems) == JSON_TYPE_BOOLEAN)
    {
        int i; for (i = nPrefixItemsLength; i < nInstanceLength; i++)
        {
            json jItem = JsonArrayGet(jaInstance, i);
            json jResult = schema_validate(jItem, joItems);

            if (JsonGetBool(jResult, "valid"))
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
                    JsonGetString(jResult, "error")
                );
                joOutput = schema_output_SetValid(joOutput, FALSE);
            }

            jaEvaluatedIndices = JsonArrayAdd(jaEvaluatedIndices, JsonInt(i));
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "items", joItems);
    }

    // contains (+minContains, maxContains)
    json jaContainsMatched = JsonArray();
    int bContainsUsed = JsonGetType(joContains) == JSON_TYPE_OBJECT || JsonGetType(joContains) == JSON_TYPE_BOOLEAN;
    if (bContainsUsed)
    {
        int nMatches = 0;
        int i; for (i = 0; i < nInstanceLength; i++)
        {
            json jItem = JsonArrayGet(jaInstance, i);
            json jResult = schema_validate(jItem, joContains);
            if (JsonGetBool(jResult, "valid"))
            {
                jaContainsMatched = JsonArrayAdd(jaContainsMatched, JsonInt(i));
                nMatches++;
            }
        }
        int nMin = JsonGetType(jiMinContains) == JSON_TYPE_INTEGER ? JsonGetInt(jiMinContains) : 1;
        int nMax = JsonGetType(jiMaxContains) == JSON_TYPE_INTEGER ? JsonGetInt(jiMaxContains) : 0x7FFFFFFF;

        if (nMatches < nMin)
            return schema_output_SetError(joOutput, "instance does not contain enough items matching 'contains'");
        if (nMatches > nMax)
            return schema_output_SetError(joOutput, "instance contains too many items matching 'contains'");
        joOutput = schema_output_InsertAnnotation(joOutput, "contains", joContains);
        if (JsonGetType(jiMinContains) == JSON_TYPE_INTEGER)
            joOutput = schema_output_InsertAnnotation(joOutput, "minContains", jiMinContains);
        if (JsonGetType(jiMaxContains) == JSON_TYPE_INTEGER)
            joOutput = schema_output_InsertAnnotation(joOutput, "maxContains", jiMaxContains);
        int i; for (; i < JsonGetLength(jaContainsMatched); i++)
            jaEvaluatedIndices = JsonArrayAdd(jaEvaluatedIndices, JsonArrayGet(jaContainsMatched, i));
    }

    // unevaluatedItems
    if (JsonGetType(joUnevaluatedItems) == JSON_TYPE_OBJECT || JsonGetType(joUnevaluatedItems) == JSON_TYPE_BOOLEAN)
    {
        json joEvalMap = JsonObject();
        int i; for (; i < JsonGetLength(jaEvaluatedIndices); i++)
            joEvalMap = JsonObjectSet(joEvalMap, IntToString(JsonGetInt(JsonArrayGet(jaEvaluatedIndices, i))), JsonTrue());
        
        for (i = 0; i < nInstanceLength; i++)
        {
            if (!JsonObjectHas(joEvalMap, IntToString(i)))
            {
                json jItem = JsonArrayGet(jaInstance, i);
                json jResult = schema_validate(jItem, joUnevaluatedItems);

                if (JsonGetBool(jResult, "valid"))
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
                        JsonGetString(jResult, "error")
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
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_SetError(joOutput, "instance is not an object");

    json jaMissing = JsonArray();
    int nRequiredLength = JsonGetLength(jaRequired);
    int i; for (; i < nRequiredLength; i++)
    {
        string sProperty = JsonGetString(JsonArrayGet(jaRequired, i));
        if (JsonFind(joInstance, JsonString(sProperty)) == JsonNull())
            jaMissing = JsonArrayInsert(jaMissing, JsonString(sProperty));
    }

    if (JsonGetLength(jaMissing) > 0)
        schema_output_InsertError(joOutput, "instance missing required properties");
    else
        schema_output_InsertAnnotation(joOutput, "required", jaRequired);
}

/// @brief Validates the object "minProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jiMinProperties The schema value for "minProperties".
/// @returns An output object containing the validation result.
json schema_validate_MinProperties(json joInstance, json jiMinProperties)
{
    json joOutput = schema_output_GetOutputObject();
    
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_SetError(joOutput, "instance is not an object");
    
    if (JsonGetLength(joInstance) < JsonGetInt(jiMinProperties))
        joOutput = schema_output_InsertError(joOutput, "instance has fewer properties than minProperties");
    else
        joOutput = schema_output_InsertAnnotation(joOutput, "minProperties", jiMinProperties);
}

/// @brief Validates the object "maxProperties" keyword.
/// @param joInstance The object instance to validate.
/// @param jiMaxProperties The schema value for "maxProperties".
/// @returns An output object containing the validation result.
json schema_validate_MaxProperties(json joInstance, json jiMaxProperties)
{
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_SetError(joOutput, "instance is not an object");

    if (JsonGetLength(joInstance) > JsonGetInt(jiMaxProperties))
        joOutput = schema_output_InsertError(joOutput, "instance has more properties than maxProperties");
    else
        joOutput = schema_output_InsertAnnotation(joOutput, "maxProperties", jiMaxProperties);
}

/// @brief Validates the object "dependentRequired" keyword.
/// @param joInstance The object instance to validate.
/// @param joDependentRequired The schema value for "dependentRequired".
/// @returns An output object containing the validation result.
json schema_validate_DependentRequired(json joInstance, json joDependentRequired)
{
    json joOutput = schema_output_GetOutputObject();
    
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_SetError(joOutput, "instance is not an object");

    json jaPropertyKeys = JsonObjectKeys(joDependentRequired);
    int i; for (; i < JsonGetLength(joDependentRequired); i++)
    {
        string sPropertyKey = JsonGetString(JsonArrayGet(jaPropertyKeys, i));
        if (JsonFind(joInstance, JsonArrayGet(jaPropertyKeys, i)) != JsonNull())
        {
            // the instance contains this property, so we need to see if it has all the other deps
            json jaDependencies = JsonObjectGet(joDependentRequired, sPropertyKey);
            int i; for (; i < JsonGetLength(jaDependencies); i++)
            {
                string sProperty = JsonGetString(JsonArrayGet(jaDependencies, i));
                if (JsonFind(joInstance, JsonArrayGet(jaDependencies, i)) == JsonNull())
                    joOutput = schema_output_InsertError(joOutput, "instance missing required dependency '" + sProperty + "'");
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
    json joOutput = schema_output_GetOutputObject();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return schema_output_SetError(joOutput, "instance is not an object");

    json joEvaluated = JsonObject(); // Track evaluated properties by name
    json jaInstanceKeys = JsonObjectKeys(joInstance);

    // 1. properties
    if (JsonGetType(joProperties) == JSON_TYPE_OBJECT)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(joProperties, JsonString(key)) != JsonNull())
            {
                joEvaluated = JsonObjectSet(joEvaluated, key, JSON_TRUE);
                json joPropSchema = JsonObjectGet(joProperties, key);
                json joResult = schema_validate(JsonObjectGet(joInstance, key), joPropSchema);
                if (schema_ouput_GetValid(joResult))
                    joOutput = schema_output_InsertAnnotation(joOutput, "properties", JsonString(key));
                else
                    joOutput = schema_output_InsertError(joOutput, "property '" + key + "': " + JsonGetString(joResult, "error"));
            }
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
                if (RegexMatch(key, pattern))
                {
                    joEvaluated = JsonObjectSet(joEvaluated, key, JSON_TRUE);
                    json joPatSchema = JsonObjectGet(joPatternProperties, pattern);
                    json joResult = schema_validate(JsonObjectGet(joInstance, key), joPatSchema);
                    if (schema_ouput_GetValid(joResult))
                        joOutput = schema_output_InsertAnnotation(joOutput, "patternProperties", JsonString(key));
                    else
                        joOutput = schema_output_InsertError(joOutput, "pattern property '" + key + "' (pattern: " + pattern + "): " + JsonGetString(joResult, "error"));
                }
            }
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "patternProperties", joPatternProperties);
    }

    // 3. additionalProperties
    // Only applies to properties not matched by properties or patternProperties
    if (JsonGetType(joAdditionalProperties) == JSON_TYPE_OBJECT || JsonGetType(joAdditionalProperties) == JSON_TYPE_BOOLEAN)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(joEvaluated, JsonString(key)) == JsonNull())
            {
                if (JsonGetType(joAdditionalProperties) == JSON_TYPE_BOOLEAN && !JsonGetBool(joAdditionalProperties))
                    joOutput = schema_output_InsertError(joOutput, "additional property '" + key + "' is not allowed");
                else if (JsonGetType(joAdditionalProperties) == JSON_TYPE_OBJECT)
                {
                    json joResult = schema_validate(JsonObjectGet(joInstance, key), joAdditionalProperties);
                    if (schema_ouput_GetValid(joResult))
                        joOutput = schema_output_InsertAnnotation(joOutput, "additionalProperties", JsonString(key));
                    else
                        joOutput = schema_output_InsertError(joOutput, "additional property '" + key + "': " + JsonGetString(joResult, "error"));
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
                json joResult = schema_validate(joInstance, joDepSchema);
                if (schema_ouput_GetValid(joResult))
                    joOutput = schema_output_InsertAnnotation(joOutput, "dependentSchemas", JsonString(depKey));
                else
                    joOutput = schema_output_InsertError(joOutput, "dependent schema for property '" + depKey + "': " + JsonGetString(joResult, "error"));
            }
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "dependentSchemas", joDependentSchemas);
    }

    // 5. propertyNames
    if (JsonGetType(joPropertyNames) == JSON_TYPE_OBJECT || JsonGetType(joPropertyNames) == JSON_TYPE_BOOLEAN)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            json joResult = schema_validate(JsonString(key), joPropertyNames);
            if (schema_ouput_GetValid(joResult))
                joOutput = schema_output_InsertAnnotation(joOutput, "propertyNames", JsonString(key));
            else
                joOutput = schema_output_InsertError(joOutput, "property name '" + key + "' is invalid: " + JsonGetString(joResult, "error"));
        }
        joOutput = schema_output_InsertAnnotation(joOutput, "propertyNames", joPropertyNames);
    }

    // 6. unevaluatedProperties
    if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_OBJECT || JsonGetType(joUnevaluatedProperties) == JSON_TYPE_BOOLEAN)
    {
        int i, len = JsonGetLength(jaInstanceKeys);
        for (i = 0; i < len; ++i)
        {
            string key = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
            if (JsonFind(joEvaluated, JsonString(key)) == JsonNull())
            {
                if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_BOOLEAN && !JsonGetBool(joUnevaluatedProperties))
                    joOutput = schema_output_InsertError(joOutput, "unevaluated property '" + key + "' is not allowed");
                else if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_OBJECT)
                {
                    json joResult = schema_validate(JsonObjectGet(joInstance, key), joUnevaluatedProperties);
                    if (schema_ouput_GetValid(joResult))
                        joOutput = schema_output_InsertAnnotation(joOutput, "unevaluatedProperties", JsonString(key));
                    else
                        joOutput = schema_output_InsertError(joOutput, "unevaluated property '" + key + "': " + JsonGetString(joResult, "error"));
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
    json joOutput = schema_output_GetOutputObject();

    if (schema_output_GetValid(schema_validate(jInstance, joNot)))
        return schema_output_InsertError(joOutput, "instance matches schema in 'not'");
    else
        return schema_output_InsertAnnotation(joOutput, "not", joNot);
}

/// @brief Validates the applicator "allOf" keyword
/// @param jInstance The instance to validate.
/// @param jaAllOf The schema value for "allOf".
/// @returns An output object containing the validation result.
json schema_validate_AllOf(json jInstance, json jaAllOf)
{
    json joOutput = schema_output_GetOutputObject();

    int i; for (; i < JsonGetLength(jaAllOf); i++)
    {
        if (!schema_output_GetValid(schema_validate(jInstance, JsonArrayGet(jaAllOf, i))))
            return schema_output_InsertError(joOutput, "instance does not match all schemas in 'allOf'");
    }

    return schema_output_InsertAnnotation(joOutput, "allOf", jaAllOf);
}

/// @brief Validates the applicator "anyOf" keyword
/// @param jInstance The instance to validate.
/// @param jaAnyOf The schema value for "anyOf".
/// @returns An output object containing the validation result.
json schema_validate_AnyOf(json jInstance, json jaAnyOf)
{
    json joOutput = schema_output_GetOutputObject();

    int i; for (; i < JsonGetLength(jaAnyOf); i++)
    {
        if (schema_output_GetValid(schema_validate(jInstance, JsonArrayGet(jaAnyOf, i))))
            return schema_output_InsertAnnotation(joOutput, "anyOf", jaAnyOf);
    }

    return schema_output_InsertError(joOutput, "instance does not match any schemas in 'anyOf'");
}

/// @brief Validates the applicator "oneOf" keyword
/// @param jInstance The instance to validate.
/// @param jaOneOf The schema value for "oneOf".
/// @returns An output object containing the validation result.
json schema_validate_OneOf(json jInstance, json jaOneOf)
{
    json joOutput = schema_output_GetOutputObject();

    int nMatches;
    int i; nMatches = 0;
    for (i = 0; i < JsonGetLength(jaOneOf); i++)
    {
        if (schema_output_GetValid(schema_validate(jInstance, JsonArrayGet(jaOneOf, i))))
        {
            if (++nMatches > 1)
                break;
        }
    }

    if (nMatches == 1)
        return schema_output_InsertAnnotation(joOutput, "oneOf", jaOneOf);
    else
        return schema_output_InsertError(joOutput, "instance does not match exactly one schema in 'oneOf'");
}

/// @brief Validates interdependent applicator keywords "if", "then", "else".
/// @param joInstance The object instance to validate.
/// @param joIf The schema value for "if".
/// @param joThen The schema value for "then".
/// @param joElse The schema value for "else".
/// @returns An output object containing the validation result.
json schema_validate_If(json jInstance, json joIf, json joThen, json joElse)
{
    json joOutput = schema_output_GetOutputObject();

    if (schema_output_GetValid(schema_validate(jInstance, joIf)))
    {
        if (JsonGetType(joThen) != JSON_TYPE_NULL)
        {
            if (!schema_output_GetValid(schema_validate(jInstance, joThen)))
                return schema_output_InsertError(joOutput, "instance is valid against 'if' but fails 'then'");
        }
    }
    else
    {
        if (JsonGetType(joElse) != JSON_TYPE_NULL)
        {
            if (!schema_output_GetValid(schema_validate(jInstance, joElse)))
                return schema_output_InsertError(joOutput, "instance is not valid against 'if' but fails 'else'");
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
    json joOutput = schema_output_GetOutputObject();
    return schema_output_InsertAnnotation(joOutput, sKey, jValue);
}



/// @todo add an "output" node input variable, that starts as JSON_NULL
/// This is the initial function, not the recursive one.
json schema_validate_Validate(json jInstance, json jSchema, json joOutput = JSON_NULL)
{


}
