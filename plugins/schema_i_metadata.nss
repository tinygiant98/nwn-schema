// --- Metadata Vocabulary Handlers ---

// title: annotation, must be string in schema validation
json schema_ValidateTitle(json joInstance, json joTitle, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joTitle) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/title", "title must be a string.");
        }
    }
    // No effect on instance validation
    return joResult;
}

// description: annotation, must be string in schema validation
json schema_ValidateDescription(json joInstance, json joDescription, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joDescription) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/description", "description must be a string.");
        }
    }
    // No effect on instance validation
    return joResult;
}

// default: annotation, any type allowed, so no check needed (could check existence only)
json schema_ValidateDefault(json joInstance, json joDefault, string sPointer, json joResult, int isSchemaValidation)
{
    // Any value allowed for default, no type check per spec
    return joResult;
}

// deprecated: annotation, must be boolean in schema validation, warning if true in instance validation
json schema_ValidateDeprecated(json joInstance, json joDeprecated, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joDeprecated) != JSON_TYPE_BOOL) {
            joResult = schema_ResultAddError(joResult, sPointer + "/deprecated", "deprecated must be a boolean.");
        }
    } else {
        if (JsonGetType(joDeprecated) == JSON_TYPE_BOOL && JsonGetBool(joDeprecated)) {
            joResult = schema_ResultAddError(joResult, sPointer + "/deprecated", "Warning: This property is deprecated.");
        }
    }
    return joResult;
}

// readOnly: annotation, must be boolean in schema validation
json schema_ValidateReadOnly(json joInstance, json joReadOnly, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joReadOnly) != JSON_TYPE_BOOL) {
            joResult = schema_ResultAddError(joResult, sPointer + "/readOnly", "readOnly must be a boolean.");
        }
    }
    // No effect on instance validation (unless enforcing input/output mode, which is out of scope)
    return joResult;
}

// writeOnly: annotation, must be boolean in schema validation
json schema_ValidateWriteOnly(json joInstance, json joWriteOnly, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joWriteOnly) != JSON_TYPE_BOOL) {
            joResult = schema_ResultAddError(joResult, sPointer + "/writeOnly", "writeOnly must be a boolean.");
        }
    }
    // No effect on instance validation (unless enforcing input/output mode, which is out of scope)
    return joResult;
}

// examples: annotation, must be array in schema validation
json schema_ValidateExamples(json joInstance, json joExamples, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joExamples) != JSON_TYPE_ARRAY) {
            joResult = schema_ResultAddError(joResult, sPointer + "/examples", "examples must be an array.");
        }
    }
    // No effect on instance validation
    return joResult;
}