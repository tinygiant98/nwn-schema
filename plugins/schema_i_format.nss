// --- Annotation/Assertion Vocabulary: format ---

// format: annotation; must be string in schema validation, instance validation is optional assertion
json schema_ValidateFormat(json joInstance, json joFormat, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joFormat) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/format", "format must be a string.");
        }
        return joResult;
    }
    // Instance validation: format is OPTIONAL. You may warn or ignore, unless strict mode is desired.
    // Example: If you want to enforce "format" for some formats, plug in handlers here.
    // By default, JSON Schema treats it as annotation only, so do nothing:
    return joResult;
}

// --- format (with a simple implementation for common types) ---
json schema_ValidateFormat(json joInstance, json joFormat, string sPointer, json joResult)
{
    // Basic implementation for a few common formats
    if (JsonGetType(joInstance) == JSON_TYPE_STRING && JsonGetType(joFormat) == JSON_TYPE_STRING)
    {
        string format = JsonGetString(joFormat);
        string value = JsonGetString(joInstance);

        // date-time: ISO 8601 format, e.g., "2020-12-31T23:59:59Z"
        if (format == "date-time")
        {
            if (!RegexMatch(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/format", "Value is not a valid date-time format.");
            }
        }
        // email: very basic check
        else if (format == "email")
        {
            if (!RegexMatch(value, "^[^@]+@[^@]+\\.[^@]+$"))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/format", "Value is not a valid email address.");
            }
        }
        // uri: basic check
        else if (format == "uri")
        {
            if (!RegexMatch(value, "^[a-zA-Z][a-zA-Z0-9+\\-.]*:"))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/format", "Value is not a valid URI.");
            }
        }
        // hostname: basic check
        else if (format == "hostname")
        {
            if (!RegexMatch(value, "^[a-zA-Z0-9.-]+$"))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/format", "Value is not a valid hostname.");
            }
        }
        // ipv4
        else if (format == "ipv4")
        {
            if (!RegexMatch(value, "^([0-9]{1,3}\\.){3}[0-9]{1,3}$"))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/format", "Value is not a valid IPv4 address.");
            }
        }
        // ipv6
        else if (format == "ipv6")
        {
            if (!RegexMatch(value, "^[0-9a-fA-F:]+$"))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/format", "Value is not a valid IPv6 address.");
            }
        }
        // (Add more as desired)
        // else: treat as annotation only (no error)
    }
    return joResult;
}
