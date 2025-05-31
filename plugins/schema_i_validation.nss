// --- Validation Vocabulary Handlers ---

// type: string or array of strings
json schema_ValidateType(json joInstance, json joType, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        int typ = JsonGetType(joType);
        if (typ == JSON_TYPE_STRING) return joResult;
        if (typ == JSON_TYPE_ARRAY) {
            int i;
            for (i = 0; i < JsonGetLength(joType); i++) {
                if (JsonGetType(JsonArrayGet(joType, i)) != JSON_TYPE_STRING) {
                    joResult = schema_ResultAddError(joResult, sPointer + "/type", "All values in type array must be strings.");
                }
            }
            return joResult;
        }
        joResult = schema_ResultAddError(joResult, sPointer + "/type", "type must be a string or array of strings.");
        return joResult;
    }
    // Instance validation
    int match = 0;
    int typ = JsonGetType(joType);
    if (typ == JSON_TYPE_STRING) {
        if (schema_MatchesType(JsonGetType(joInstance), JsonGetString(joType))) match = 1;
    } else if (typ == JSON_TYPE_ARRAY) {
        int i;
        for (i = 0; i < JsonGetLength(joType); i++) {
            if (schema_MatchesType(JsonGetType(joInstance), JsonGetString(JsonArrayGet(joType, i)))) match = 1;
        }
    }
    if (!match) {
        joResult = schema_ResultAddError(joResult, sPointer + "/type", "Instance type does not match schema type.");
    }
    return joResult;
}

// const: instance must be deeply equal to the const value
json schema_ValidateConst(json joInstance, json joConst, string sPointer, json joResult, int isSchemaValidation)
{
    // Any value allowed for const in schema
    if (isSchemaValidation) return joResult;
    if (!JsonEquals(joInstance, joConst)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/const", "Instance does not match the const value.");
    }
    return joResult;
}

// enum: array of allowed values
json schema_ValidateEnum(json joInstance, json joEnum, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joEnum) != JSON_TYPE_ARRAY) {
            joResult = schema_ResultAddError(joResult, sPointer + "/enum", "enum must be an array.");
        }
        return joResult;
    }
    int i, found = 0;
    for (i = 0; i < JsonGetLength(joEnum); i++) {
        if (JsonEquals(joInstance, JsonArrayGet(joEnum, i))) found = 1;
    }
    if (!found) {
        joResult = schema_ResultAddError(joResult, sPointer + "/enum", "Instance value is not in enum.");
    }
    return joResult;
}

// multipleOf: number must be a multiple of the value
json schema_ValidateMultipleOf(json joInstance, json joMultipleOf, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMultipleOf) != JSON_TYPE_INTEGER && JsonGetType(joMultipleOf) != JSON_TYPE_FLOAT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/multipleOf", "multipleOf must be a number.");
        }
        return joResult;
    }
    int typ = JsonGetType(joInstance);
    if (typ != JSON_TYPE_INTEGER && typ != JSON_TYPE_FLOAT) return joResult;
    float val = JsonToFloat(joInstance);
    float factor = JsonToFloat(joMultipleOf);
    if (factor == 0.0) return joResult;
    float rem = val / factor;
    if (Abs(rem - Round(rem)) > 1e-10) {
        joResult = schema_ResultAddError(joResult, sPointer + "/multipleOf", "Number is not a multiple of value.");
    }
    return joResult;
}

// maximum, exclusiveMaximum, minimum, exclusiveMinimum: number comparison
json schema_ValidateMaximum(json joInstance, json joMaximum, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMaximum) != JSON_TYPE_INTEGER && JsonGetType(joMaximum) != JSON_TYPE_FLOAT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/maximum", "maximum must be a number.");
        }
        return joResult;
    }
    int typ = JsonGetType(joInstance);
    if (typ != JSON_TYPE_INTEGER && typ != JSON_TYPE_FLOAT) return joResult;
    if (JsonToFloat(joInstance) > JsonToFloat(joMaximum)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/maximum", "Number is greater than maximum.");
    }
    return joResult;
}

json schema_ValidateExclusiveMaximum(json joInstance, json joExclusiveMaximum, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joExclusiveMaximum) != JSON_TYPE_INTEGER && JsonGetType(joExclusiveMaximum) != JSON_TYPE_FLOAT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMaximum", "exclusiveMaximum must be a number.");
        }
        return joResult;
    }
    int typ = JsonGetType(joInstance);
    if (typ != JSON_TYPE_INTEGER && typ != JSON_TYPE_FLOAT) return joResult;
    if (JsonToFloat(joInstance) >= JsonToFloat(joExclusiveMaximum)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMaximum", "Number is greater than or equal to exclusiveMaximum.");
    }
    return joResult;
}

json schema_ValidateMinimum(json joInstance, json joMinimum, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMinimum) != JSON_TYPE_INTEGER && JsonGetType(joMinimum) != JSON_TYPE_FLOAT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/minimum", "minimum must be a number.");
        }
        return joResult;
    }
    int typ = JsonGetType(joInstance);
    if (typ != JSON_TYPE_INTEGER && typ != JSON_TYPE_FLOAT) return joResult;
    if (JsonToFloat(joInstance) < JsonToFloat(joMinimum)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/minimum", "Number is less than minimum.");
    }
    return joResult;
}

json schema_ValidateExclusiveMinimum(json joInstance, json joExclusiveMinimum, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joExclusiveMinimum) != JSON_TYPE_INTEGER && JsonGetType(joExclusiveMinimum) != JSON_TYPE_FLOAT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMinimum", "exclusiveMinimum must be a number.");
        }
        return joResult;
    }
    int typ = JsonGetType(joInstance);
    if (typ != JSON_TYPE_INTEGER && typ != JSON_TYPE_FLOAT) return joResult;
    if (JsonToFloat(joInstance) <= JsonToFloat(joExclusiveMinimum)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMinimum", "Number is less than or equal to exclusiveMinimum.");
    }
    return joResult;
}

// maxLength, minLength: string length
json schema_ValidateMaxLength(json joInstance, json joMaxLength, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMaxLength) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxLength", "maxLength must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_STRING) return joResult;
    if (StrLen(JsonGetString(joInstance)) > JsonGetInt(joMaxLength)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/maxLength", "String is longer than maxLength.");
    }
    return joResult;
}

json schema_ValidateMinLength(json joInstance, json joMinLength, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMinLength) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/minLength", "minLength must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_STRING) return joResult;
    if (StrLen(JsonGetString(joInstance)) < JsonGetInt(joMinLength)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/minLength", "String is shorter than minLength.");
    }
    return joResult;
}

// pattern: string must match regex
json schema_ValidatePattern(json joInstance, json joPattern, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joPattern) != JSON_TYPE_STRING) {
            joResult = schema_ResultAddError(joResult, sPointer + "/pattern", "pattern must be a string.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_STRING) return joResult;
    if (!RegexMatch(JsonGetString(joInstance), JsonGetString(joPattern))) {
        joResult = schema_ResultAddError(joResult, sPointer + "/pattern", "String does not match pattern.");
    }
    return joResult;
}

// maxItems, minItems: array length
json schema_ValidateMaxItems(json joInstance, json joMaxItems, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMaxItems) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxItems", "maxItems must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY) return joResult;
    if (JsonGetLength(joInstance) > JsonGetInt(joMaxItems)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/maxItems", "Array has more items than maxItems.");
    }
    return joResult;
}

json schema_ValidateMinItems(json joInstance, json joMinItems, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMinItems) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/minItems", "minItems must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY) return joResult;
    if (JsonGetLength(joInstance) < JsonGetInt(joMinItems)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/minItems", "Array has fewer items than minItems.");
    }
    return joResult;
}

// uniqueItems: array elements must be unique
json schema_ValidateUniqueItems(json joInstance, json joUniqueItems, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joUniqueItems) != JSON_TYPE_BOOL) {
            joResult = schema_ResultAddError(joResult, sPointer + "/uniqueItems", "uniqueItems must be a boolean.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY || !JsonGetBool(joUniqueItems)) return joResult;
    int i, j, n = JsonGetLength(joInstance);
    for (i = 0; i < n; i++) {
        for (j = i + 1; j < n; j++) {
            if (JsonEquals(JsonArrayGet(joInstance, i), JsonArrayGet(joInstance, j))) {
                joResult = schema_ResultAddError(joResult, sPointer + "/uniqueItems", "Array has duplicate items.");
                return joResult;
            }
        }
    }
    return joResult;
}

// maxContains, minContains: array, count of items matching "contains"
json schema_ValidateMaxContains(json joInstance, json joMaxContains, json joSchema, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMaxContains) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxContains", "maxContains must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY) return joResult;
    if (!JsonObjectHasKey(joSchema, "contains")) return joResult;
    json containsSchema = JsonObjectGet(joSchema, "contains");
    int i, count = 0, n = JsonGetLength(joInstance);
    for (i = 0; i < n; i++) {
        json tempResult = JsonObject();
        tempResult = schema_Validate(JsonArrayGet(joInstance, i), containsSchema, JsonArray(), JsonArray(), sPointer + "/contains/" + IntToString(i), tempResult, 0);
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0) count++;
    }
    if (count > JsonGetInt(joMaxContains)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/maxContains", "Too many items matched 'contains'.");
    }
    return joResult;
}

json schema_ValidateMinContains(json joInstance, json joMinContains, json joSchema, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMinContains) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/minContains", "minContains must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY) return joResult;
    if (!JsonObjectHasKey(joSchema, "contains")) return joResult;
    json containsSchema = JsonObjectGet(joSchema, "contains");
    int i, count = 0, n = JsonGetLength(joInstance);
    for (i = 0; i < n; i++) {
        json tempResult = JsonObject();
        tempResult = schema_Validate(JsonArrayGet(joInstance, i), containsSchema, JsonArray(), JsonArray(), sPointer + "/contains/" + IntToString(i), tempResult, 0);
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0) count++;
    }
    if (count < JsonGetInt(joMinContains)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/minContains", "Too few items matched 'contains'.");
    }
    return joResult;
}

// maxProperties, minProperties: number of object properties
json schema_ValidateMaxProperties(json joInstance, json joMaxProperties, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMaxProperties) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxProperties", "maxProperties must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT) return joResult;
    if (JsonGetLength(JsonObjectKeys(joInstance)) > JsonGetInt(joMaxProperties)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/maxProperties", "Object has more properties than maxProperties.");
    }
    return joResult;
}

json schema_ValidateMinProperties(json joInstance, json joMinProperties, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joMinProperties) != JSON_TYPE_INTEGER) {
            joResult = schema_ResultAddError(joResult, sPointer + "/minProperties", "minProperties must be an integer.");
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT) return joResult;
    if (JsonGetLength(JsonObjectKeys(joInstance)) < JsonGetInt(joMinProperties)) {
        joResult = schema_ResultAddError(joResult, sPointer + "/minProperties", "Object has fewer properties than minProperties.");
    }
    return joResult;
}

// required: array of strings, all must be present as properties
json schema_ValidateRequired(json joInstance, json joRequired, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joRequired) != JSON_TYPE_ARRAY) {
            joResult = schema_ResultAddError(joResult, sPointer + "/required", "required must be an array.");
        } else {
            int i;
            for (i = 0; i < JsonGetLength(joRequired); i++) {
                if (JsonGetType(JsonArrayGet(joRequired, i)) != JSON_TYPE_STRING) {
                    joResult = schema_ResultAddError(joResult, sPointer + "/required", "Each value in required array must be a string.");
                }
            }
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT) return joResult;
    int i;
    for (i = 0; i < JsonGetLength(joRequired); i++) {
        string req = JsonGetString(JsonArrayGet(joRequired, i));
        if (!JsonObjectHasKey(joInstance, req)) {
            joResult = schema_ResultAddError(joResult, sPointer + "/required", "Required property '" + req + "' is missing.");
        }
    }
    return joResult;
}

// dependentRequired: object, key = property name, value = array of property names that are required if key is present
json schema_ValidateDependentRequired(json joInstance, json joDependentRequired, string sPointer, json joResult, int isSchemaValidation)
{
    if (isSchemaValidation) {
        if (JsonGetType(joDependentRequired) != JSON_TYPE_OBJECT) {
            joResult = schema_ResultAddError(joResult, sPointer + "/dependentRequired", "dependentRequired must be an object.");
        } else {
            json keys = JsonObjectKeys(joDependentRequired);
            int i;
            for (i = 0; i < JsonGetLength(keys); i++) {
                string key = JsonGetString(JsonArrayGet(keys, i));
                json arr = JsonObjectGet(joDependentRequired, key);
                if (JsonGetType(arr) != JSON_TYPE_ARRAY) {
                    joResult = schema_ResultAddError(joResult, sPointer + "/dependentRequired/" + key, "Each value in dependentRequired must be an array.");
                } else {
                    int j;
                    for (j = 0; j < JsonGetLength(arr); j++) {
                        if (JsonGetType(JsonArrayGet(arr, j)) != JSON_TYPE_STRING) {
                            joResult = schema_ResultAddError(joResult, sPointer + "/dependentRequired/" + key, "Each value in dependentRequired array must be a string.");
                        }
                    }
                }
            }
        }
        return joResult;
    }
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT || JsonGetType(joDependentRequired) != JSON_TYPE_OBJECT) return joResult;
    json keys = JsonObjectKeys(joDependentRequired);
    int i;
    for (i = 0; i < JsonGetLength(keys); i++) {
        string key = JsonGetString(JsonArrayGet(keys, i));
        if (JsonObjectHasKey(joInstance, key)) {
            json arr = JsonObjectGet(joDependentRequired, key);
            int j;
            for (j = 0; j < JsonGetLength(arr); j++) {
                string dep = JsonGetString(JsonArrayGet(arr, j));
                if (!JsonObjectHasKey(joInstance, dep)) {
                    joResult = schema_ResultAddError(joResult, sPointer + "/dependentRequired/" + key, "Property '" + dep + "' is required when '" + key + "' is present.");
                }
            }
        }
    }
    return joResult;
}