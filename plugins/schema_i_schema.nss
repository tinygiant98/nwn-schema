// --- Schema Vocabulary Handlers ---

// definitions: object of named subschemas (legacy, like $defs)
json schema_ValidateDefinitions(json joInstance, json joDefinitions, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joDefinitions) != JSON_TYPE_OBJECT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/definitions", "definitions must be an object.");
        } else {
            // Optionally, can recurse into definitions for nested schema validation
            // json keys = JsonObjectKeys(joDefinitions);
            // int i;
            // for (i = 0; i < JsonGetLength(keys); i++) {
            //     string key = JsonGetString(JsonArrayGet(keys, i));
            //     joResult = schema_Validate(JsonObjectGet(joDefinitions, key), <meta-schema>, ...);
            // }
        }
    }
    // No effect on instance validation
    return joResult;
}

// dependencies: object, key = property name, value = schema or array of strings
json schema_ValidateDependencies(json joInstance, json joDependencies, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joDependencies) != JSON_TYPE_OBJECT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/dependencies", "dependencies must be an object.");
        } else {
            json keys = JsonObjectKeys(joDependencies);
            int i;
            for (i = 0; i < JsonGetLength(keys); i++) {
                string key = JsonGetString(JsonArrayGet(keys, i));
                json val = JsonObjectGet(joDependencies, key);
                int typ = JsonGetType(val);
                if (typ == JSON_TYPE_OBJECT) {
                    // Recursively check subschema if desired
                } else if (typ == JSON_TYPE_ARRAY) {
                    int j;
                    for (j = 0; j < JsonGetLength(val); j++) {
                        if (JsonGetType(JsonArrayGet(val, j)) != JSON_TYPE_STRING) {
                            joResult = schema_ResultAddError(joResult, sPointer + "/dependencies/" + key, "Each item in dependency array must be a string.");
                        }
                    }
                } else {
                    joResult = schema_ResultAddError(joResult, sPointer + "/dependencies/" + key, "Each dependency value must be an object or an array of strings.");
                }
            }
        }
        return joResult;
    }

    // Instance validation
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT || JsonGetType(joDependencies) != JSON_TYPE_OBJECT)
        return joResult;

    json keys = JsonObjectKeys(joDependencies);
    int i;
    for (i = 0; i < JsonGetLength(keys); i++)
    {
        string key = JsonGetString(JsonArrayGet(keys, i));
        if (!JsonObjectHasKey(joInstance, key)) continue;
        json dep = JsonObjectGet(joDependencies, key);
        int typ = JsonGetType(dep);
        if (typ == JSON_TYPE_OBJECT)
        {
            joResult = schema_Validate(joInstance, dep, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/dependencies/" + key, joResult, 0);
        }
        else if (typ == JSON_TYPE_ARRAY)
        {
            int j;
            for (j = 0; j < JsonGetLength(dep); j++)
            {
                string depKey = JsonGetString(JsonArrayGet(dep, j));
                if (!JsonObjectHasKey(joInstance, depKey))
                {
                    joResult = schema_ResultAddError(joResult, sPointer + "/dependencies/" + key, "Property '" + depKey + "' is required by dependency on '" + key + "'.");
                }
            }
        }
    }
    return joResult;
}

// $recursiveAnchor: must be boolean if present (schema validation), annotation only
json schema_ValidateRecursiveAnchor(json joInstance, json joRecursiveAnchor, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joRecursiveAnchor) != JSON_TYPE_BOOL) {
            joResult = schema_ResultAddError(joResult, sPointer + "/$recursiveAnchor", "$recursiveAnchor must be a boolean.");
        }
    }
    // No effect on instance validation
    return joResult;
}

// $recursiveRef: must be string if present (schema validation), annotation only
json schema_ValidateRecursiveRef(json joInstance, json joRecursiveRef, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joRecursiveRef) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/$recursiveRef", "$recursiveRef must be a string.");
        }
    }
    // Actual recursive reference resolution is handled at the main validation function level, not here
    return joResult;
}