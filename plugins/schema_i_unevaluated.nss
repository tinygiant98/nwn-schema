// --- Unevaluated Vocabulary Handlers ---

// unevaluatedItems: schema applied to array items NOT already validated by prefixItems/items/contains
json schema_ValidateUnevaluatedItems(
    json joInstance,
    json joUnevaluatedItems,
    json joSchema, // parent schema for context
    string sPointer,
    json joResult,
    json jaAnchorScope,
    json jaDynamicAnchorScope,
    int isSchemaValidation
)
{
    if (isSchemaValidation) {
        // Must be boolean or object
        int typ = JsonGetType(joUnevaluatedItems);
        if (typ != JSON_TYPE_BOOL && typ != JSON_TYPE_OBJECT)
            joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedItems", "unevaluatedItems must be a boolean or an object.");
        return joResult;
    }

    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY)
        return joResult;

    // Determine which indices were already validated by prefixItems, items, contains, etc.
    int len = JsonGetLength(joInstance);
    int i, evaluated[len];
    for (i = 0; i < len; i++) evaluated[i] = 0;

    // Mark all indices as evaluated by prefixItems
    if (JsonObjectHasKey(joSchema, "prefixItems") && JsonGetType(JsonObjectGet(joSchema, "prefixItems")) == JSON_TYPE_ARRAY) {
        int plen = JsonGetLength(JsonObjectGet(joSchema, "prefixItems"));
        for (i = 0; i < len && i < plen; i++) evaluated[i] = 1;
    }
    // Mark all indices as evaluated by items (if items is an array)
    if (JsonObjectHasKey(joSchema, "items") && JsonGetType(JsonObjectGet(joSchema, "items")) == JSON_TYPE_ARRAY) {
        int ilen = JsonGetLength(JsonObjectGet(joSchema, "items"));
        for (i = 0; i < len && i < ilen; i++) evaluated[i] = 1;
    }
    // Mark by contains (all items matching contains are evaluated)
    if (JsonObjectHasKey(joSchema, "contains") && JsonGetType(JsonObjectGet(joSchema, "contains")) == JSON_TYPE_OBJECT) {
        json containsSchema = JsonObjectGet(joSchema, "contains");
        for (i = 0; i < len; i++) {
            json tempResult = JsonObject();
            tempResult = schema_Validate(JsonArrayGet(joInstance, i), containsSchema, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/contains/" + IntToString(i), tempResult, 0);
            json errors = JsonObjectGet(tempResult, "errors");
            if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
                evaluated[i] = 1;
        }
    }

    // Now validate unevaluated items
    int typ = JsonGetType(joUnevaluatedItems);
    for (i = 0; i < len; i++) {
        if (!evaluated[i]) {
            if (typ == JSON_TYPE_BOOL) {
                if (!JsonGetBool(joUnevaluatedItems)) {
                    joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedItems/" + IntToString(i), "Additional array item not allowed at index " + IntToString(i) + ".");
                }
            } else if (typ == JSON_TYPE_OBJECT) {
                joResult = schema_Validate(JsonArrayGet(joInstance, i), joUnevaluatedItems, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/unevaluatedItems/" + IntToString(i), joResult, 0);
            }
        }
    }
    return joResult;
}

// unevaluatedProperties: schema applied to object properties NOT already validated by properties, patternProperties, or additionalProperties
json schema_ValidateUnevaluatedProperties(
    json joInstance,
    json joUnevaluatedProperties,
    json joSchema, // parent schema for context
    string sPointer,
    json joResult,
    json jaAnchorScope,
    json jaDynamicAnchorScope,
    int isSchemaValidation
)
{
    if (isSchemaValidation) {
        // Must be boolean or object
        int typ = JsonGetType(joUnevaluatedProperties);
        if (typ != JSON_TYPE_BOOL && typ != JSON_TYPE_OBJECT)
            joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedProperties", "unevaluatedProperties must be a boolean or an object.");
        return joResult;
    }

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return joResult;

    // Determine which keys are already validated
    json propKeys = JsonObjectKeys(joInstance);
    int i, n = JsonGetLength(propKeys);
    int evaluated[n];
    for (i = 0; i < n; i++) evaluated[i] = 0;

    // Mark all properties present in "properties" as evaluated
    if (JsonObjectHasKey(joSchema, "properties") && JsonGetType(JsonObjectGet(joSchema, "properties")) == JSON_TYPE_OBJECT) {
        json pkeys = JsonObjectKeys(JsonObjectGet(joSchema, "properties"));
        int j, plen = JsonGetLength(pkeys);
        for (i = 0; i < n; i++) {
            string key = JsonGetString(JsonArrayGet(propKeys, i));
            for (j = 0; j < plen; j++) {
                string pkey = JsonGetString(JsonArrayGet(pkeys, j));
                if (key == pkey) evaluated[i] = 1;
            }
        }
    }
    // Mark all properties matching patternProperties as evaluated
    if (JsonObjectHasKey(joSchema, "patternProperties") && JsonGetType(JsonObjectGet(joSchema, "patternProperties")) == JSON_TYPE_OBJECT) {
        json patKeys = JsonObjectKeys(JsonObjectGet(joSchema, "patternProperties"));
        int j, patLen = JsonGetLength(patKeys);
        for (i = 0; i < n; i++) {
            string key = JsonGetString(JsonArrayGet(propKeys, i));
            for (j = 0; j < patLen; j++) {
                string pat = JsonGetString(JsonArrayGet(patKeys, j));
                if (RegexMatch(key, pat)) evaluated[i] = 1;
            }
        }
    }
    // Mark all properties matched by additionalProperties as evaluated
    if (JsonObjectHasKey(joSchema, "additionalProperties")) {
        // If additionalProperties is false, any extra property is not allowed and would already have errored.
        // If additionalProperties is a schema, those properties are considered evaluated.
        json addlProps = JsonObjectGet(joSchema, "additionalProperties");
        if (JsonGetType(addlProps) == JSON_TYPE_OBJECT) {
            for (i = 0; i < n; i++) {
                if (!evaluated[i]) evaluated[i] = 1;
            }
        }
    }

    // Now validate unevaluated properties
    int typ = JsonGetType(joUnevaluatedProperties);
    for (i = 0; i < n; i++) {
        if (!evaluated[i]) {
            string key = JsonGetString(JsonArrayGet(propKeys, i));
            if (typ == JSON_TYPE_BOOL) {
                if (!JsonGetBool(joUnevaluatedProperties)) {
                    joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedProperties/" + key, "Additional property '" + key + "' is not allowed.");
                }
            } else if (typ == JSON_TYPE_OBJECT) {
                joResult = schema_Validate(JsonObjectGet(joInstance, key), joUnevaluatedProperties, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/unevaluatedProperties/" + key, joResult, 0);
            }
        }
    }
    return joResult;
}