// --- Core Vocabulary Handlers ---

// $id: annotation only, but must be a string in schema validation
json schema_ValidateId(json joInstance, json joId, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joId) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/$id", "$id must be a string.");
        }
    }
    // No effect on instance validation
    return joResult;
}

// $schema: annotation only, must be a string in schema validation
json schema_ValidateSchema(json joInstance, json joSchemaKeyword, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joSchemaKeyword) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/$schema", "$schema must be a string.");
        }
    }
    // No effect on instance validation
    return joResult;
}

// $vocabulary: annotation only, must be an object in schema validation, values must be boolean
json schema_ValidateVocabulary(json joInstance, json joVocabulary, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joVocabulary) != JSON_TYPE_OBJECT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/$vocabulary", "$vocabulary must be an object.");
        } else {
            json keys = JsonObjectKeys(joVocabulary);
            int i;
            for (i = 0; i < JsonGetLength(keys); i++) {
                string key = JsonGetString(JsonArrayGet(keys, i));
                if (JsonGetType(JsonObjectGet(joVocabulary, key)) != JSON_TYPE_BOOL) {
                    joResult = schema_ResultAddError(joResult, sPointer + "/$vocabulary/" + key, "Each value in $vocabulary must be a boolean.");
                }
            }
        }
    }
    // No effect on instance validation
    return joResult;
}

// $comment: annotation only, must be a string in schema validation
json schema_ValidateComment(json joInstance, json joComment, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joComment) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/$comment", "$comment must be a string.");
        }
    }
    // No effect on instance validation
    return joResult;
}

// $defs: object of named subschemas
json schema_ValidateDefs(json joInstance, json joDefs, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joDefs) != JSON_TYPE_OBJECT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/$defs", "$defs must be an object.");
        } else {
            // Optionally, could recurse to validate all nested subschemas in $defs
            // json keys = JsonObjectKeys(joDefs);
            // int i;
            // for (i = 0; i < JsonGetLength(keys); i++) {
            //     string key = JsonGetString(JsonArrayGet(keys, i));
            //     joResult = schema_Validate(JsonObjectGet(joDefs, key), <meta-schema>, ...);
            // }
        }
    }
    // No effect on instance validation
    return joResult;
}