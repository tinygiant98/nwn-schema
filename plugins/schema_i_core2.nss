
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
///    output of schema validation, as defined by json-schema.org.  This includes full validaty,
///    error and annotations for each json object in the instance.  Functions are provided to pare
///    down the output to the user's desired verbosity level.

json schema_output_Set(json joOutput, string sKey, json jValue)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT || sKey == "" || JsonGetType(jValue) == JSON_TYPE_NULL)
        return joOutput;

    return JsonObjectSet(joOutput, sKey, jValue);
}

json schema_output_SetValid(json joOutput, json jbValue)
{
    return schema_output_Set(joOutput, "valid", jbValue);
}

json schema_output_SetKeywordLocation(json joOutput, json jsLocation)
{
    return schema_output_Set(joOutput, "keywordLocation", jsLocation);
}

json schema_output_SetAbsoluteKeywordLocation(json joOutput, json jsLocation)
{
    return schema_output_Set(joOutput, "absoluteKeywordLocation", jsLocation);
}

json schema_output_SetInstanceLocation(json joOutput, json jsLocation)
{
    return schema_output_Set(joOutput, "instanceLocation", jsLocation);
}

schema_output_PushError(json joOutput, json joError)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT || JsonGetType(joError) != JSON_TYPE_OBJECT)
        return joOutput;

    json jaErrors = JsonObjectGet(joOutput, "errors");
    if (JsonGetType(jaErrors) != JSON_TYPE_ARRAY)
        jaErrors = JsonArray();

    return JsonArrayInsert(jaErrors, joError);
}

json schema_output_SetError(json joOutput, json jError)
{
    if (JsonGetType(jError) == JSON_TYPE_STRING)
    {
        joOutput = schema_output_SetValid(joOutput, JSON_FALSE);
        return schema_output_Set(joOutput, "error", jError);
    }
    else if (JsonGetType(jError) == JSON_TYPE_OBJECT)
    {
        joOutput = schema_output_SetValid(joOutput, JSON_FALSE);
        return schema_output_Set(joOutput, "errors", schema_output_PushError(joOutput, jError));
    }

    return joOutput;
}

json schema_output_PushAnnotation(json joOutput, json joAnnotation)
{
    if (JsonGetType(joOutput) != JSON_TYPE_OBJECT || JsonGetType(joAnnotation) != JSON_TYPE_OBJECT)
        return joOutput;

    json jaAnnotations = JsonObjectGet(joOutput, "annotations");
    if (JsonGetType(jaAnnotations) != JSON_TYPE_ARRAY)
        jaAnnotations = JsonArray();

    return schema_output_Set(joOutput, "annotations", JsonArrayInsert(jaAnnotations, joAnnotation));
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

/// @brief Validates the "type" keyword.
/// @param jInstance The instance to validate.
/// @param jType The schema value for "type".
/// @returns TRUE if the instance matches the type, FALSE otherwise.
/// @note This functions calls itself recursively to handle arrays of types.
int schema_validate_Type(json jInstance, json jType)
{
    /// @todo this check should be handled in the caller to build the correct error.
    if (JsonGetType(jType) != JSON_TYPE_STRING && JsonGetType(jType) != JSON_TYPE_ARRAY)
        return FALSE;

    int nInstanceType = JsonGetType(jInstance);

    if (JsonGetType(jType) == JSON_TYPE_STRING)
    {
        if (JsonGetString(jType) == "number")
            return nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT;

        json jaTypes = JsonParse(r"
            ""null"",
            ""object"",
            ""array"",
            ""string"",
            ""integer"",
            ""float"",
            ""boolean""
        ");

        if (JsonFind(jaTypes, jType) == JsonNull())
            return FALSE;

        return nInstanceType == JsonGetInt(JsonFind(jaTypes, jType));
    }

    int i; for (; i < JsonGetLength(jType); i++)
    {
        if (schema_validate_Type(jInstance, JsonArrayGet(jType, i)))
            return TRUE;
    }

    return FALSE;
}

/// @brief Validates the "enum" keyword.
/// @param jInstance The instance to validate.
/// @param jaEnum The schema value for "enum".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct
///     - 0x02 (Bit 1): enum type is correct
///     - 0x04 (Bit 2): enum value is correct
///     - 0x08 (Bit 3): enum constraint met
/// @note Due to NWN's nlohmann::json implementation, JsonFind() conducts a
///     deep comparison of the instance and enum values; separate handling
///     for the various json types is not required.
int schema_validate_Enum(json jInstance, json jaEnum)
{
    int INSTANCE_TYPE   = 0x01;
    int ENUM_TYPE       = 0x02;
    int ENUM_VALUE      = 0x04;
    int ENUM_CONSTRAINT = 0x08;

    int nResult = FALSE;

    if (JsonGetType(jInstance) != JSON_TYPE_NULL)
        nResult |= INSTANCE_TYPE;

    if (JsonGetType(jsEnum) != JSON_TYPE_NULL)
    {
        if (JsonGetType(jaEnum) == JSON_TYPE_ARRAY)
        {
            nResult |= ENUM_TYPE;

            if (JsonGetLength(jaEnum) > 0)
                nResult |= ENUM_VALUE;

            if (JsonFind(jaEnum, jInstance) != JsonNull())
                nResult |= ENUM_CONSTRAINT;
        }
    }
    else
        nResult |= (ENUM_TYPE | ENUM_VALUE | ENUM_CONSTRAINT);

    return nResult;
}

/// @brief Validates the "const" keyword.
/// @param jInstance The instance to validate.
/// @param jConst The schema value for "const".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct
///     - 0x02 (Bit 1): const type is correct
///     - 0x04 (Bit 2): const value is correct
///     - 0x08 (Bit 3): const constraint met
int schema_validate_Const(json jInstance, json jConst)
{
    return schema_validate_Enum(jInstance, JsonArrayInsert(JsonArray(), jConst));
}

/// @brief Validates the string's "minLength" keyword.
/// @param jsInstance The instance to validate.
/// @param jiMinLength The schema value for "minLength".
/// @returns TRUE if the instance is at least the min length, FALSE otherwise.
int schema_validate_MinLength(json jsInstance, json jiMinLength)
{
    if (JsonGetType(jsInstance) != JSON_TYPE_STRING || JsonGetType(jiMinLength) != JSON_TYPE_INTEGER)
        return FALSE;

    int nMinLength = JsonGetInt(jiMinLength);
    return nMinLength >= 0 && GetStringLength(JsonGetString(jsInstance)) >= nMinLength;
}

/// @brief Validates the string's "maxLength" keyword.
/// @param jInstance The instance to validate.
/// @param jiMaxLength The schema value for "maxLength".
/// @returns TRUE if the instance is at most the max length, FALSE otherwise.
int schema_validate_MaxLength(json jInstance, json jiMaxLength)
{
    if (JsonGetType(jInstance) != JSON_TYPE_STRING || JsonGetType(jiMaxLength) != JSON_TYPE_INTEGER)
        return FALSE;

    int nMaxLength = JsonGetInt(jiMaxLength);
    return nMaxLength >= 0 && GetStringLength(JsonGetString(jInstance)) <= nMaxLength;
}

/// @brief Validates the string's "pattern" keyword.
/// @param jInstance The instance to validate.
/// @param jsPattern The schema value for "pattern".
/// @returns TRUE if the instance matches the regex pattern, FALSE otherwise.
int schema_validate_Pattern(json jInstance, json jsPattern)
{
    if (JsonGetType(jInstance) != JSON_TYPE_STRING || JsonGetType(jsPattern) != JSON_TYPE_STRING)
        return FALSE;

    return RegExpMatch(JsonGetString(jsPattern), JsonGetString(jInstance)) != JsonArray();
}

/// @brief Validates the string's "format" keyword for all standard formats defined by JSON Schema.
/// @param jsInstance The instance to validate.
/// @param jsFormat The schema value for "format".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct (string)
///     - 0x02 (Bit 1): format type is correct (string or null)
///     - 0x04 (Bit 2): format value is correct (known format string or null)
///     - 0x08 (Bit 3): format constraint met (value matches format)
/// @note If the constraint is not applicable (e.g., the keyword is not present),
///     it is considered met for the purpose of this validation.
/// @note Only a subset of formats can be validated strictly; others may use basic regex or partial checks.
int schema_validate_Format(json jsInstance, json jsFormat)
{
    /// @todo neeeds a  lot of work

    int INSTANCE_TYPE         = 0x01;
    int FORMAT_TYPE           = 0x02;
    int FORMAT_VALUE          = 0x04;
    int FORMAT_CONSTRAINT     = 0x08;

    int nResult = FALSE;

    if (JsonGetType(jInstance) == JSON_TYPE_STRING)
    {
        nResult |= INSTANCE_TYPE;
        int nFormatType = JsonGetType(jFormat);

        if (nFormatType != JSON_TYPE_NULL)
        {
            if (nFormatType == JSON_TYPE_STRING)
            {
                nResult |= FORMAT_TYPE;
                
                string sFormat = JsonGetString(jFormat);
                string sValue = JsonGetString(jInstance);

                int bValidFormat = TRUE;
                int bFormatMatched = FALSE;

                // Validate all official JSON Schema formats
                if (sFormat == "date-time")
                {
                    nResult |= FORMAT_VALUE;
                    // Simple RFC3339 regex, not exhaustive!
                    if (RegexMatch(sValue, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?([+-]\\d{2}:\\d{2}|Z)$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "date")
                {
                    nResult |= FORMAT_VALUE;
                    if (RegexMatch(sValue, "^\\d{4}-\\d{2}-\\d{2}$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "time")
                {
                    nResult |= FORMAT_VALUE;
                    if (RegexMatch(sValue, "^\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?([+-]\\d{2}:\\d{2}|Z)?$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "duration")
                {
                    nResult |= FORMAT_VALUE;
                    // Simple ISO 8601 duration regex
                    if (RegexMatch(sValue, "^P(T(?=\\d)(\\d+H)?(\\d+M)?(\\d+S)?|(?=\\d)(\\d+Y)?(\\d+M)?(\\d+D)?(T(\\d+H)?(\\d+M)?(\\d+S)?)?)$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "email")
                {
                    nResult |= FORMAT_VALUE;
                    if (RegexMatch(sValue, "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "idn-email")
                {
                    nResult |= FORMAT_VALUE;
                    // Accept as email (not full IDN validation)
                    if (RegexMatch(sValue, "^[^@]+@[^@]+$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "hostname")
                {
                    nResult |= FORMAT_VALUE;
                    if (RegexMatch(sValue, "^[A-Za-z0-9.-]+$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "idn-hostname")
                {
                    nResult |= FORMAT_VALUE;
                    // Accept as hostname (not full IDN validation)
                    if (RegexMatch(sValue, "^[A-Za-z0-9.-]+$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "ipv4")
                {
                    nResult |= FORMAT_VALUE;
                    if (RegexMatch(sValue, "^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "ipv6")
                {
                    nResult |= FORMAT_VALUE;
                    // Not a full IPv6 regex, just checks for ":"
                    if (FindSubString(sValue, ":") != -1)
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "uri")
                {
                    nResult |= FORMAT_VALUE;
                    if (RegexMatch(sValue, "^[a-zA-Z][a-zA-Z0-9+.-]*:"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "uri-reference")
                {
                    nResult |= FORMAT_VALUE;
                    // Accept as URI or relative reference (very basic)
                    if (RegexMatch(sValue, "^[a-zA-Z][a-zA-Z0-9+.-]*:") || RegexMatch(sValue, "^/"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "iri")
                {
                    nResult |= FORMAT_VALUE;
                    // Accept as URI (not full IRI validation)
                    if (RegexMatch(sValue, "^[a-zA-Z][a-zA-Z0-9+.-]*:"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "iri-reference")
                {
                    nResult |= FORMAT_VALUE;
                    // Accept as IRI or relative (very basic)
                    if (RegexMatch(sValue, "^[a-zA-Z][a-zA-Z0-9+.-]*:") || RegexMatch(sValue, "^/"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "uri-template")
                {
                    nResult |= FORMAT_VALUE;
                    // Accept as URI template (very basic: must contain '{' and '}')
                    if (FindSubString(sValue, "{") != -1 && FindSubString(sValue, "}") != -1)
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "json-pointer")
                {
                    nResult |= FORMAT_VALUE;
                    // JSON pointer must start with / or be empty
                    if (sValue == "" || RegexMatch(sValue, "^(/([^/~]|~[01])*)*$"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "relative-json-pointer")
                {
                    nResult |= FORMAT_VALUE;
                    // Basic check: must start with a number
                    if (RegexMatch(sValue, "^\\d+"))
                        bFormatMatched = TRUE;
                }
                else if (sFormat == "regex")
                {
                    nResult |= FORMAT_VALUE;
                    // Accept any string as regex for now
                    bFormatMatched = TRUE;
                }
                else if (sFormat == "uuid")
                {
                    nResult |= FORMAT_VALUE;
                    if (RegexMatch(sValue, "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"))
                        bFormatMatched = TRUE;
                }
                else
                {
                    // Unknown format: treat as valid as per spec
                    bValidFormat = FALSE;
                }

                if (!bValidFormat)
                {
                    // Unknown format: always considered met per spec
                    nResult |= (FORMAT_VALUE | FORMAT_CONSTRAINT);
                }
                else if (bFormatMatched)
                {
                    nResult |= FORMAT_CONSTRAINT;
                }
            }
        }
        else
            nResult |= (FORMAT_TYPE | FORMAT_VALUE | FORMAT_CONSTRAINT);
    }

    return nResult;
}

/// @brief Validates the number's "minimum" and "exclusiveMinimum" keywords.
/// @param jInstance The instance to validate.
/// @param jMinimum The schema value for "minimum".
/// @param jExclusiveMinimum The schema value for "exclusiveMinimum".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct
///     - 0x02 (Bit 1): minimum type is correct
///     - 0x04 (Bit 2): minimum value is correct
///     - 0x08 (Bit 3): minimum constraint met
///     - 0x10 (Bit 4): exclusiveMinimum type is correct
///     - 0x20 (Bit 5): exclusiveMinimum value is correct
///     - 0x40 (Bit 6); exclusiveMinimum constraint met
/// @note If a constraint is not applicable (e.g., the keyword is not present),
///     it is considered met for the purpose of this validation.
int schema_validate_Minimum(json jInstance, json jMinimum, json jExclusiveMinimum)
{
    int INSTANCE_TYPE                = 0x01;
    int MINIMUM_TYPE                 = 0x02;
    int MINIMUM_VALUE                = 0x04;
    int MINIMUM_CONSTRAINT           = 0x08;
    int EXCLUSIVE_MINIMUM_TYPE       = 0x10;
    int EXCLUSIVE_MINIMUM_VALUE      = 0x20;
    int EXCLUSIVE_MINIMUM_CONSTRAINT = 0x40;
        
    int nResult = FALSE;
    int nInstanceType = JsonGetType(jInstance);

    if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
    {
        nResult |= INSTANCE_TYPE;

        float fInstance = JsonGetFloat(jInstance);
        int nMinimumType = JsonGetType(jMinimum);
        if (nMinimumType != JSON_TYPE_NULL)
        {
            if (nMinimumType == JSON_TYPE_INTEGER || nMinimumType == JSON_TYPE_FLOAT)
            {
                nResult |= (MINIMUM_TYPE | MINIMUM_VALUE);
                if (fInstance >= JsonGetFloat(jMinimum))
                    nResult |= MINIMUM_CONSTRAINT;
            }
        }
        else
            nResult |= (MINIMUM_TYPE | MINIMUM_VALUE | MINIMUM_CONSTRAINT);

        int nExclusiveMinimumType = JsonGetType(jExclusiveMinimum);
        if (nExclusiveMinimumType != JSON_TYPE_NULL)
        {
            if (nExclusiveMinimumType == JSON_TYPE_INTEGER || nExclusiveMinimumType == JSON_TYPE_FLOAT)
            {
                nResult |= (EXCLUSIVE_MINIMUM_TYPE | EXCLUSIVE_MINIMUM_VALUE);
                if (fInstance > JsonGetFloat(jExclusiveMinimum))
                    nResult |= EXCLUSIVE_MINIMUM_CONSTRAINT;
            }
        }
        else
            nResult |= (EXCLUSIVE_MINIMUM_TYPE | EXCLUSIVE_MINIMUM_VALUE | EXCLUSIVE_MINIMUM_CONSTRAINT);
    }

    return nResult;
}

/// @brief Validates the number's "maximum" and "exclusiveMaximum" keywords.
/// @param jInstance The instance to validate.
/// @param jMaximum The schema value for "maximum".
/// @param jExclusiveMaximum The schema value for "exclusiveMaximum".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct
///     - 0x02 (Bit 1): maximum type is correct
///     - 0x04 (Bit 2): maximum value is correct
///     - 0x08 (Bit 3): maximum constraint met
///     - 0x10 (Bit 4): exclusiveMaximum type is correct
///     - 0x20 (Bit 5): exclusiveMaximum value is correct
///     - 0x40 (Bit 6): exclusiveMaximum constraint met
/// @note If a constraint is not applicable (e.g., the keyword is not present),
///     it is considered met for the purpose of this validation.
int schema_validate_Maximum(json jInstance, json jMaximum, json jExclusiveMaximum)
{
    int INSTANCE_TYPE                 = 0x01;
    int MAXIMUM_TYPE                  = 0x02;
    int MAXIMUM_VALUE                 = 0x04;
    int MAXIMUM_CONSTRAINT            = 0x08;
    int EXCLUSIVE_MAXIMUM_TYPE        = 0x10;
    int EXCLUSIVE_MAXIMUM_VALUE       = 0x20;
    int EXCLUSIVE_MAXIMUM_CONSTRAINT  = 0x40;
        
    int nResult = FALSE;
    int nInstanceType = JsonGetType(jInstance);

    if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
    {
        nResult |= INSTANCE_TYPE;

        float fInstance = JsonGetFloat(jInstance);
        int nMaximumType = JsonGetType(jMaximum);
        if (nMaximumType != JSON_TYPE_NULL)
        {
            if (nMaximumType == JSON_TYPE_INTEGER || nMaximumType == JSON_TYPE_FLOAT)
            {
                nResult |= (MAXIMUM_TYPE | MAXIMUM_VALUE);
                if (fInstance <= JsonGetFloat(jMaximum))
                    nResult |= MAXIMUM_CONSTRAINT;
            }
        }
        else
            nResult |= (MAXIMUM_TYPE | MAXIMUM_VALUE | MAXIMUM_CONSTRAINT);

        int nExclusiveMaximumType = JsonGetType(jExclusiveMaximum);
        if (nExclusiveMaximumType != JSON_TYPE_NULL)
        {
            if (nExclusiveMaximumType == JSON_TYPE_INTEGER || nExclusiveMaximumType == JSON_TYPE_FLOAT)
            {
                nResult |= (EXCLUSIVE_MAXIMUM_TYPE | EXCLUSIVE_MAXIMUM_VALUE);
                if (fInstance < JsonGetFloat(jExclusiveMaximum))
                    nResult |= EXCLUSIVE_MAXIMUM_CONSTRAINT;
            }
        }
        else
            nResult |= (EXCLUSIVE_MAXIMUM_TYPE | EXCLUSIVE_MAXIMUM_VALUE | EXCLUSIVE_MAXIMUM_CONSTRAINT);
    }

    return nResult;
}

/// @brief Validates the number's "multipleOf" keyword.
/// @param jInstance The instance to validate.
/// @param jMultipleOf The schema value for "multipleOf".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01: instance type is correct
///     - 0x02: multipleOf type is correct
///     - 0x04: multipleOf value is correct
///     - 0x08: multipleOf constraint met
/// @note If the constraint is not applicable (e.g., the keyword is not present),
///     it is considered met for the purpose of this validation.
int schema_validate_MultipleOf(json jInstance, json jMultipleOf)
{
    int INSTANCE_TYPE         = 0x01;
    int MULTIPLEOF_TYPE       = 0x02;
    int MULTIPLEOF_VALUE      = 0x04;
    int MULTIPLEOF_CONSTRAINT = 0x08;

    int nResult = FALSE;
    int nInstanceType = JsonGetType(jInstance);

    if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
    {
        nResult |= INSTANCE_TYPE;

        float fInstance = JsonGetFloat(jInstance);
        int nMultipleOfType = JsonGetType(jMultipleOf);

        if (nMultipleOfType != JSON_TYPE_NULL)
        {
            if (nMultipleOfType == JSON_TYPE_INTEGER || nMultipleOfType == JSON_TYPE_FLOAT)
            {
                nResult |= MULTIPLEOF_TYPE;
                float fMultipleOf = JsonGetFloat(jMultipleOf);
                if (fMultipleOf > 0.0)
                {
                    nResult |= MULTIPLEOF_VALUE;

                    float fRem = fInstance / fMultipleOf;
                    float fDiff = fRem - IntToFloat(FloatToInt(fRem));
                    if (fabs(fDiff) < 0.00001)
                        nResult |= MULTIPLEOF_CONSTRAINT;
                }
            }
        }
        else
            nResult |= (MULTIPLEOF_TYPE | MULTIPLEOF_VALUE | MULTIPLEOF_CONSTRAINT);
    }

    return nResult;
}

/// @brief Validates the "minItems" keyword for arrays.
/// @param jInstance The instance to validate.
/// @param jiMinItems The schema value for "minItems".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct (array)
///     - 0x02 (Bit 1): minItems type is correct (integer)
///     - 0x04 (Bit 2): minItems value is correct (>= 0)
///     - 0x08 (Bit 3): constraint met (array length >= minItems)
int schema_validate_MinItems(json jInstance, json jiMinItems)
{
    int INSTANCE_TYPE         = 0x01;
    int MINITEMS_TYPE         = 0x02;
    int MINITEMS_VALUE        = 0x04;
    int MINITEMS_CONSTRAINT   = 0x08;

    int nResult = FALSE;
    if (JsonGetType(jInstance) == JSON_TYPE_ARRAY)
    {
        nResult |= INSTANCE_TYPE;

        int nMinItemsType = JsonGetType(jiMinItems);
        if (nMinItemsType != JSON_TYPE_NULL)
        {
            if (nMinItemsType == JSON_TYPE_INTEGER)
            {
                nResult |= MINITEMS_TYPE;
                int nMinItems = JsonGetInt(jiMinItems);
                if (nMinItems >= 0)
                {
                    nResult |= MINITEMS_VALUE;
                    if (JsonGetLength(jInstance) >= nMinItems)
                        nResult |= MINITEMS_CONSTRAINT;
                }
            }
        }
        else
            nResult |= (MINITEMS_TYPE | MINITEMS_VALUE | MINITEMS_CONSTRAINT);
    }

    return nResult;
}

/// @brief Validates the "maxItems" keyword for arrays.
/// @param jInstance The instance to validate.
/// @param jiMaxItems The schema value for "maxItems".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct (array)
///     - 0x02 (Bit 1): maxItems type is correct (integer)
///     - 0x04 (Bit 2): maxItems value is correct (>= 0)
///     - 0x08 (Bit 3): constraint met (array length <= maxItems)
int schema_validate_MaxItems(json jInstance, json jiMaxItems)
{
    int INSTANCE_TYPE         = 0x01;
    int MAXITEMS_TYPE         = 0x02;
    int MAXITEMS_VALUE        = 0x04;
    int MAXITEMS_CONSTRAINT   = 0x08;

    int nResult = FALSE;
    if (JsonGetType(jInstance) == JSON_TYPE_ARRAY)
    {
        nResult |= INSTANCE_TYPE;

        int nMaxItemsType = JsonGetType(jiMaxItems);
        if (nMaxItemsType != JSON_TYPE_NULL)
        {
            if (nMaxItemsType == JSON_TYPE_INTEGER)
            {
                nResult |= MAXITEMS_TYPE;
                int nMaxItems = JsonGetInt(jiMaxItems);
                if (nMaxItems >= 0)
                {
                    nResult |= MAXITEMS_VALUE;
                    if (JsonGetLength(jInstance) <= nMaxItems)
                        nResult |= MAXITEMS_CONSTRAINT;
                }
            }
        }
        else
            nResult |= (MAXITEMS_TYPE | MAXITEMS_VALUE | MAXITEMS_CONSTRAINT);
    }
    
    return nResult;
}

/// @brief Validates the "uniqueItems" keyword for arrays.
/// @param jInstance The instance to validate.
/// @param jbUniqueItems The schema value for "uniqueItems".
/// @returns A bitmask indicating which constraints were met:
///     - 0x01 (Bit 0): instance type is correct (array)
///     - 0x02 (Bit 1): uniqueItems type is correct (boolean)
///     - 0x04 (Bit 2): uniqueItems value is correct (true/false)
///     - 0x08 (Bit 3): constraint met
int schema_validate_UniqueItems(json jInstance, json jbUniqueItems)
{
    int INSTANCE_TYPE             = 0x01;
    int UNIQUEITEMS_TYPE          = 0x02;
    int UNIQUEITEMS_VALUE         = 0x04;
    int UNIQUEITEMS_CONSTRAINT    = 0x08;

    int nResult = FALSE;

    if (JsonGetType(jInstance) == JSON_TYPE_ARRAY)
    {
        nResult |= INSTANCE_TYPE;

        int nUniqueItemsType = JsonGetType(jbUniqueItems);
        if (nUniqueItemsType != JSON_TYPE_NULL)
        {
            if (nUniqueItemsType == JSON_TYPE_BOOLEAN)
            {
                nResult |= (UNIQUEITEMS_TYPE | UNIQUEITEMS_VALUE);
                if (jbUniqueItems == JSON_FALSE)
                    nResult |= UNIQUEITEMS_CONSTRAINT;
                else if (jbUniqueItems == JSON_TRUE)
                {
                    if (JsonGetLength(jInstance) == JsonGetLength(JsonArrayTransform(jInstance, JSON_ARRAY_UNIQUE)))
                        nResult |= UNIQUEITEMS_CONSTRAINT;
                }
            }
        }
        else
            nResult |= (UNIQUEITEMS_TYPE | UNIQUEITEMS_VALUE | UNIQUEITEMS_CONSTRAINT);
    }

    return nResult;
}

/// @brief Validates the "items" keyword for arrays.
/// @param jaInstance The instance to validate.
/// @param jItems The schema value for "items".
/// @param jaPrefixItems The schema value for "prefixItems".
/// @param jUnevaluatedItems The schema value for "unevaluatedItems".
/// @returns A bitmask indicating which constraints were met:
///     - 0x001 (Bit 0): instance type is correct (array)
///     - 0x002 (Bit 1): items type is correct
///     - 0x004 (Bit 2): items value is correct
///     - 0x008 (Bit 3): items constraint met
///     - 0x010 (Bit 4): prefixItems type is correct
///     - 0x020 (Bit 5): prefixItems value is correct
///     - 0x040 (Bit 6): prefixItems constraint met
///     - 0x080 (Bit 7): unevaluatedItems type is correct
///     - 0x100 (Bit 8): unevaluatedItems value is correct
///     - 0x200 (Bit 9): unevaluatedItems constraint met
int schema_validate_Items(json jaInstance, json jItems, json jaPrefixItems, json jUnevaluatedItems)
{
    int INSTANCE_TYPE               = 0x001;
    int ITEMS_TYPE                  = 0x002;
    int ITEMS_VALUE                 = 0x004;
    int ITEMS_CONSTRAINT            = 0x008;
    int PREFIXITEMS_TYPE            = 0x010;
    int PREFIXITEMS_VALUE           = 0x020;
    int PREFIXITEMS_CONSTRAINT      = 0x040;
    int UNEVALUATEDITEMS_TYPE       = 0x080;
    int UNEVALUATEDITEMS_VALUE      = 0x100;
    int UNEVALUATEDITEMS_CONSTRAINT = 0x200;

    int nResult = FALSE;

    if (JsonGetType(jaInstance) == JSON_TYPE_ARRAY)
    {
        nResult |= INSTANCE_TYPE;

        if (JsonGetType(jaPrefixItems) == JSON_TYPE_ARRAY)
        {
            nResult |= PREFIXITEMS_TYPE;
            if (JsonGetLength(jaPrefixItems) > 0)
            {
                nResult |= (PREFIXITEMS_VALUE | PREFIXITEMS_CONSTRAINT);
                int i; for (; i < JsonGetLength(jaPrefixItems) && i < JsonGetLength(jaInstance); i++)
                {
                    /// @todo schema validate the individual items to the
                    ///   recurse function, which doesn't exist yet?
                    ///   This isn't the right function name .......
                    int bValid = schmea_validate_Validate(JsonArrayGet(jaInstance, i), JsonArrayGet(jaPrefixItems, i));
                    if (!bValid)
                        nResult &= ~PREFIXITEMS_CONSTRAINT;
                }
            }
        }
        else if (JsonGetType(jaPrefixItems) == JSON_TYPE_NULL)
            nResult |= (PREFIXITEMS_TYPE | PREFIXITEMS_VALUE | PREFIXITEMS_CONSTRAINT);
    }

    if (JsonGetType(jItems) != JSON_TYPE_NULL)
    {
        nResult |= (ITEMS_TYPE | ITEMS_VALUE | ITEMS_CONSTRAINT);
        int i; for (i = JsonGetLength(jaPrefixItems); i < JsonGetLength(jaInstance); i++)
        {
            /// @todo get the right function name here.....
            int bValid = schmea_validate_Validate(JsonArrayGet(jaInstance, i), jItems);
            if (!bValid)
                nResult &= ~ITEMS_CONSTRAINT;
        }
    }
    else
        nResult |= (ITEMS_TYPE | ITEMS_VALUE | ITEMS_CONSTRAINT);

    if (JsonGetType(jUnevaluatedItems) != JSON_TYPE_NULL)
    {
        nResult = (UNEVALUATEDITEMS_TYPE | UNEVALUATEDITEMS_VALUE);

        int nPrefixItemsType = JsonGetType(jaPrefixItems);
        int nPrefixItemsLength = JsonGetLength(jaPrefixItems);

        if (JsonGetType(jItems) == JSON_TYPE_NULL &&
            (nPrefixItemsType == JSON_TYPE_NULL ||
            (nPrefixItemsType == JSON_TYPE_ARRAY && nPrefixItemsLength < JsonGetLength(jaInstance))))
        {
            int nIndex = 0;
            if (nPrefixItemsType == JSON_TYPE_ARRAY && nPrefixItemsLength < JsonGetLength(jaInstance))
                nIndex = nPrefixItemsLength;

            nResult |= UNEVALUATEDITEMS_CONSTRAINT;
            int i; for (i = nIndex; i < JsonGetLength(jaInstance); i++)
            {
                /// @todo get the right function name here ......
                int bValid = schema_validate(JsonArrayGet(jaInstance, i), jUnevaluatedItems);
                if (!bValid)
                    nResult &= ~UNEVALUATEDITEMS_CONSTRAINT;
            }
        }
    }
    else
        nResult |= (UNEVALUATEDITEMS_TYPE | UNEVALUATEDITEMS_VALUE | UNEVALUATEDITEMS_CONSTRAINT);

    return nResult;
}















/// @todo add an "output" node input variable, that starts as JSON_NULL
/// This is the initial function, not the recursive one.
json schema_validate_Validate(json jInstance, json jSchema, json joOutput = JSON_NULL)
{
    if (joOutput == JSON_NULL)
        /// @todo actually needs to be the default output object
        joOutput = JsonObject();
        /// @todo joOutput = schema_output_GetDefaultNode(///send in instance to get base data?///);

    if (JsonGetType(jInstance) == JSON_TYPE_NULL || JsonGetType(jSchema) == JSON_TYPE_NULL)
        // actually need to reutrn an error or negative validation result
    {
        /// @todo set error
        joOutput = schema_output_SetError(joOutput, "Instance or schema is null");
        return JsonObjectSet(joOutput, "valid", JSON_FALSE);
    }

    /// @note A schema must be a boolean or an object.
    if (JsonGetType(jSchema) == JSON_TYPE_BOOLEAN)
        return JsonObjectSet(joOutput, "valid", jSchema);

    if (JsonGetType(jSchema) != JSON_TYPE_OBJECT)
    {
        joOutput = schema_output_SetError(joOutput, "Schema is not an object");
        return JsonObjectSet(joOutput, "valid", JSON_FALSE);
    }

    int nInstanceType = JsonGetType(jInstance);
    if (nInstanceType == JSON_TYPE_OBJECT)
    {

    }
    else if (nInstanceType == JSON_TYPE_ARRAY)
    {

    }
    else
    {
        json jType = JsonObjectGet(jSchema, "type");
        if (JsonGetType(jType) != JSON_TYPE_NULL)
        {
            if (schema_validate_Type(jInstance, jType))



            {
                joOutput = schema_output_SetError(joOutput, "Instance does not match schema type");
                return JsonObjectSet(joOutput, "valid", JSON_FALSE);
            }
        }
    }


    /// If the instance is not an array or object, we should just check the type versus the schema
    ///     and go from there, no need to recurse into anything.
    if (JsonGetType(jInstance) != JSON_TYPE_OBJECT && JsonGetType(jInstance) != JSON_TYPE_ARRAY)
    {
        // Check the type
        json jType = JsonObjectGet(jSchema, "type");
        if (JsonGetType(jType) != JSON_TYPE_NULL)
        {
            int ok = schema_validate_Type(jInstance, jType);
            if (!ok)
            {
                joOutput = schema_output_SetError(joOutput, "Instance does not match schema type");
                return JsonObjectSet(joOutput, "valid", JSON_FALSE);
            }
        }

        // Check the enum
        json jaEnum = JsonObjectGet(jSchema, "enum");
        if (JsonGetType(jaEnum) != JSON_TYPE_NULL)
        {
            int ok = schema_validate_Enum(jInstance, jaEnum);
            if (!ok)
            {
                joOutput = schema_output_SetError(joOutput, "Instance is not in enum");
                return JsonObjectSet(joOutput, "valid", JSON_FALSE);
            }
        }

        // If we get here, the instance is valid
        return JsonObjectSet(joOutput, "valid", JSON_TRUE);
    }




    json jaInstanceKeys = JsonObjectKeys(jSchema);
    int i; for (; i < JsonGetLength(jaSchemaKeys); i++)
    {
        string sKey = JsonGetString(JsonArrayGet(jaSchemaKeys, i));

        json jValue = JsonObjectGet(jSchema, sKey);

        switch (sKey)
        {
            case "$id":
            case "$schema":
            case "$comment":
                // These keywords do not affect validation
                break;

            case "$ref":
                // Handle $ref keyword
                break;

            case "$anchor":
                // Handle $anchor keyword
                break;

            case "type":
                int ok = schema_validate_Type(jInstance, jValue);
                /// @todo output node
                break;

            case "enum":
                if (JsonGetType(jaEnum) != JSON_TYPE_ARRAY)
                    return JSON_NULL;

                int ok = schema_validate_Enum(jInstance, jValue);
                break;

            default:
                // Handle other keywords as needed
                break;
        }
    }


    return joOutput;

}

















json schema_validate_Validate(json jInstance, json joSchema)
{
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
        return JsonNull();

    json jTypes = JsonObjectGet(joSchema, "type");
    /// @todo make sure the instance type is in jTypes

    /// Ok, time to handle $anchors
    json jaAnchorScope = JsonArray(), jsAnchor = JsonObjectGet(joSchema, "$anchor");
    if (JsonGetType(jsAnchor) == JSON_TYPE_STRING)
    {
        jaAnchorScope = schema_reference_PushAnchor(jaAnchorScope, JsonGetString(jsAnchor), )
    }


}

json schema_validate_ValidateSchema(json jSchema)
{
    // This function is a placeholder for the actual schema validation logic.
    // It should return a JSON object containing the validation results.
    // For now, we will return a simple valid response.
    
    json joOutput = JsonObject();
    joOutput = schema_output_SetValid(joOutput, JSON_TRUE);
    
    // Add any additional processing or validation logic here.
    
    return joOutput;
}

json schema_validate_ValidateInstance(json jInstance, json jSchema)
{
    // This function is a placeholder for the actual validation logic.
    // It should return a JSON object containing the validation results.
    // For now, we will return a simple valid response.
    
    json joOutput = JsonObject();
    joOutput = schema_output_SetValid(joOutput, JSON_TRUE);
    
    // Add any additional processing or validation logic here.
    
    return joOutput;
}