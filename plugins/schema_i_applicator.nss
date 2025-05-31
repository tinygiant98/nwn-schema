// --- Applicator Vocabulary Handlers ---

json schema_ValidatePrefixItems(json jaInstance, json jaPrefixItems, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    int nPrefixItems = JsonGetLength(jaPrefixItems);

    // Must be an array and must not be empty (by spec)
    if (JsonGetType(jaPrefixItems) != JSON_TYPE_ARRAY || nPrefixItems == 0)
    {
        joResult = schema_ResultAddError(
            joResult,
            sPointer + "/prefixItems",
            "prefixItems must be a non-empty array."
        );
        return joResult;
    }

    // Instance must be an array for prefixItems to apply
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
    {
        joResult = schema_ResultAddError(
            joResult,
            sPointer,
            "Instance must be an array for prefixItems validation."
        );
        return joResult;
    }

    int nInstanceItems = JsonGetLength(jaInstance);
    int nLimit = (nInstanceItems < nPrefixItems) ? nInstanceItems : nPrefixItems;
    int i;
    for (i = 0; i < nLimit; i++)
    {
        joResult = schema_Validate(
            JsonArrayGet(jaInstance, i),
            JsonArrayGet(jaPrefixItems, i),
            jaAnchorScope,
            jaDynamicAnchorScope,
            sPointer + "/prefixItems/" + IntToString(i),
            joResult
        );
    }
    return joResult;
}

// items: schema or array of schemas for instance array elements beyond prefixItems
json schema_ValidateItems(json joInstance, json joItems, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY)
        return joResult;

    if (JsonGetType(joItems) == JSON_TYPE_OBJECT)
    {
        // single schema applies to all items
        int i;
        for (i = 0; i < JsonGetLength(joInstance); i++)
        {
            joResult = schema_Validate(JsonArrayGet(joInstance, i), joItems, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/items/" + IntToString(i), joResult);
        }
    }
    else if (JsonGetType(joItems) == JSON_TYPE_ARRAY)
    {
        int i, max = JsonGetLength(joItems);
        for (i = 0; i < JsonGetLength(joInstance) && i < max; i++)
        {
            joResult = schema_Validate(JsonArrayGet(joInstance, i), JsonArrayGet(joItems, i), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/items/" + IntToString(i), joResult);
        }
    }
    return joResult;
}

// contains: at least one array item must validate against subschema
json schema_ValidateContains(json joInstance, json joContains, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) != JSON_TYPE_ARRAY)
        return joResult;

    int found = 0, i;
    for (i = 0; i < JsonGetLength(joInstance); i++)
    {
        json tempResult = JsonObject();
        tempResult = schema_Validate(JsonArrayGet(joInstance, i), joContains, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/contains/" + IntToString(i), tempResult);
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
        {
            found = 1;
            break;
        }
    }
    if (!found)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/contains", "No array elements match the 'contains' schema.");
    }
    return joResult;
}

// additionalProperties: controls validation of properties not listed in "properties" or matched by "patternProperties"
json schema_ValidateAdditionalProperties(json joInstance, json joAdditionalProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return joResult;

    json joProps = JsonObjectGet(joInstance, "properties");
    json joPatProps = JsonObjectGet(joInstance, "patternProperties");

    int i;
    json keys = JsonObjectKeys(joInstance);
    for (i = 0; i < JsonGetLength(keys); i++)
    {
        string key = JsonGetString(JsonArrayGet(keys, i));
        int matched = 0;
        if (JsonGetType(joProps) == JSON_TYPE_OBJECT && JsonObjectHasKey(joProps, key))
            matched = 1;
        if (!matched && JsonGetType(joPatProps) == JSON_TYPE_OBJECT)
        {
            json patKeys = JsonObjectKeys(joPatProps);
            int j;
            for (j = 0; j < JsonGetLength(patKeys); j++)
            {
                string pat = JsonGetString(JsonArrayGet(patKeys, j));
                if (RegexMatch(key, pat))
                {
                    matched = 1;
                    break;
                }
            }
        }
        if (!matched)
        {
            if (JsonGetType(joAdditionalProperties) == JSON_TYPE_BOOL)
            {
                if (!JsonGetBool(joAdditionalProperties))
                    joResult = schema_ResultAddError(joResult, sPointer + "/additionalProperties", "Additional property '" + key + "' is not allowed.");
            }
            else if (JsonGetType(joAdditionalProperties) == JSON_TYPE_OBJECT)
            {
                joResult = schema_Validate(JsonObjectGet(joInstance, key), joAdditionalProperties, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/additionalProperties/" + key, joResult);
            }
        }
    }
    return joResult;
}

// properties: validates instance properties by per-property subschemas
json schema_ValidateProperties(json joInstance, json joProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT || JsonGetType(joProperties) != JSON_TYPE_OBJECT)
        return joResult;

    json keys = JsonObjectKeys(joProperties);
    int i;
    for (i = 0; i < JsonGetLength(keys); i++)
    {
        string key = JsonGetString(JsonArrayGet(keys, i));
        if (JsonObjectHasKey(joInstance, key))
        {
            joResult = schema_Validate(JsonObjectGet(joInstance, key), JsonObjectGet(joProperties, key), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/properties/" + key, joResult);
        }
    }
    return joResult;
}

// patternProperties: validates instance properties by regex-matched subschemas
json schema_ValidatePatternProperties(json joInstance, json joPatternProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT || JsonGetType(joPatternProperties) != JSON_TYPE_OBJECT)
        return joResult;

    json patKeys = JsonObjectKeys(joPatternProperties);
    json keys = JsonObjectKeys(joInstance);
    int i, j;
    for (i = 0; i < JsonGetLength(keys); i++)
    {
        string key = JsonGetString(JsonArrayGet(keys, i));
        for (j = 0; j < JsonGetLength(patKeys); j++)
        {
            string pat = JsonGetString(JsonArrayGet(patKeys, j));
            if (RegexMatch(key, pat))
            {
                joResult = schema_Validate(JsonObjectGet(joInstance, key), JsonObjectGet(joPatternProperties, pat), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/patternProperties/" + pat + "/" + key, joResult);
            }
        }
    }
    return joResult;
}

// dependentSchemas: object, key = property name, value = schema applied if key present in instance
json schema_ValidateDependentSchemas(json joInstance, json joDependentSchemas, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT || JsonGetType(joDependentSchemas) != JSON_TYPE_OBJECT)
        return joResult;

    json keys = JsonObjectKeys(joDependentSchemas);
    int i;
    for (i = 0; i < JsonGetLength(keys); i++)
    {
        string key = JsonGetString(JsonArrayGet(keys, i));
        if (JsonObjectHasKey(joInstance, key))
        {
            joResult = schema_Validate(joInstance, JsonObjectGet(joDependentSchemas, key), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/dependentSchemas/" + key, joResult);
        }
    }
    return joResult;
}

// propertyNames: validates all property names of an object instance
json schema_ValidatePropertyNames(json joInstance, json joPropertyNames, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return joResult;

    json keys = JsonObjectKeys(joInstance);
    int i;
    for (i = 0; i < JsonGetLength(keys); i++)
    {
        string key = JsonGetString(JsonArrayGet(keys, i));
        json tempResult = JsonObject();
        tempResult = schema_Validate(JsonString(key), joPropertyNames, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/propertyNames/" + key, tempResult);
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) == JSON_TYPE_ARRAY && JsonGetLength(errors) > 0)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/propertyNames/" + key, "Property name '" + key + "' does not match propertyNames schema.");
        }
    }
    return joResult;
}

// if/then/else: conditional validation
json schema_ValidateIf(json joInstance, json joIf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope, json joSchema)
{
    json ifResult = JsonObject();
    ifResult = schema_Validate(joInstance, joIf, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/if", ifResult);
    json errors = JsonObjectGet(ifResult, "errors");
    int ifOk = JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0;

    if (ifOk && JsonObjectHasKey(joSchema, "then"))
    {
        joResult = schema_Validate(joInstance, JsonObjectGet(joSchema, "then"), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/then", joResult);
    }
    else if (!ifOk && JsonObjectHasKey(joSchema, "else"))
    {
        joResult = schema_Validate(joInstance, JsonObjectGet(joSchema, "else"), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/else", joResult);
    }
    return joResult;
}

// allOf: instance must validate against all schemas in array
json schema_ValidateAllOf(json joInstance, json jaAllOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(jaAllOf) != JSON_TYPE_ARRAY)
        return joResult;

    int i;
    for (i = 0; i < JsonGetLength(jaAllOf); i++)
    {
        joResult = schema_Validate(joInstance, JsonArrayGet(jaAllOf, i), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/allOf/" + IntToString(i), joResult);
    }
    return joResult;
}

// anyOf: instance must validate against at least one schema in array
json schema_ValidateAnyOf(json joInstance, json jaAnyOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(jaAnyOf) != JSON_TYPE_ARRAY)
        return joResult;

    int valid = 0, i;
    for (i = 0; i < JsonGetLength(jaAnyOf); i++)
    {
        json tempResult = JsonObject();
        tempResult = schema_Validate(joInstance, JsonArrayGet(jaAnyOf, i), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/anyOf/" + IntToString(i), tempResult);
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
        {
            valid = 1;
            break;
        }
    }
    if (!valid)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/anyOf", "Instance does not match any schema in anyOf.");
    }
    return joResult;
}

// oneOf: instance must validate against exactly one schema in array
json schema_ValidateOneOf(json joInstance, json jaOneOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(jaOneOf) != JSON_TYPE_ARRAY)
        return joResult;

    int valid = 0, i;
    for (i = 0; i < JsonGetLength(jaOneOf); i++)
    {
        json tempResult = JsonObject();
        tempResult = schema_Validate(joInstance, JsonArrayGet(jaOneOf, i), jaAnchorScope, jaDynamicAnchorScope, sPointer + "/oneOf/" + IntToString(i), tempResult);
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
        {
            valid++;
        }
    }
    if (valid != 1)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/oneOf", "Instance must match exactly one schema in oneOf (" + IntToString(valid) + " matched).");
    }
    return joResult;
}

// not: instance must NOT validate against the subschema
json schema_ValidateNot(json joInstance, json joNot, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    json tempResult = JsonObject();
    tempResult = schema_Validate(joInstance, joNot, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/not", tempResult);
    json errors = JsonObjectGet(tempResult, "errors");
    if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/not", "Instance must not match schema in not.");
    }
    return joResult;
}