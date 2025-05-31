#include "util_i_debug"

/// @todo I dont' think I care or will ver care if a specific
///     vocab is active or not.  Delete?
int schema_GetVocabularyActive(string sVocabulary)
{
    sVocabulary = GetStringLeft(GetStringLowerCase(sVocabulary), 16);
    return JsonFind(GetLocalJson(GetModule(), "SCHEMA_VOCABULARIES"), JsonString(sVocabulary)) != JsonNull();
}

/// @brief Build the vocabulary for the meta schema.  This vocabulary
///    consists of the contents of each opted-in vocabulary file listed
///    in the $vocabulary key of the schema.txt file.  If the user wants
///    to opt-out of a specific vocabulary, the boolean value for that
///    key should be set to false.
void schema_BuildVocabulary(int bForce = FALSE)
{
    json jSchema = GetLocalJson(GetModule(), "SCHEMA_VOCABULARY");
    if (jSchema == JsonNull() || bForce)
    {
        jSchema = JsonObject();
        json jVocabularies = JsonArray();

        json jMeta = JsonParse(ResManGetFileContents("schema", RESTYPE_TXT));
        if (jMeta != JsonNull())
        {
            json jVocabulary = JsonObjectGet(jMeta, "$vocabulary");
            json jKeys = JsonObjectKeys(jVocabulary);
            int n; for (; n < JsonGetLength(jKeys); n++)
            {
                string sKey = JsonGetString(JsonArrayGet(jKeys, n));
                Debug("Merging vocabulary: " + sKey);
                jVocabularies = JsonArrayInsert(jVocabularies, JsonString(GetStringLowerCase(sKey)));
                if (JsonObjectGet(jVocabulary, sKey) == JSON_TRUE)
                {
                    json jFile = RegExpMatch("[^/]+$", sKey);
                    string sFile = GetStringLeft(JsonGetString(JsonArrayGet(jFile, 0)), 16);
                    Debug("  Merging file: " + sFile);
                    jSchema = JsonMerge(jSchema, JsonParse(ResManGetFileContents(sFile, RESTYPE_TXT)));
                    Debug("  Merged Schema: " + JsonDump(jSchema, 4));
                }
            }

            jSchema = JsonMerge(jSchema, JsonParse(ResManGetFileContents("nwn", RESTYPE_TXT)));
        }

        SetLocalJson(GetModule(), "SCHEMA_VOCABULARY", jSchema);

        /// @todo do i need this?  If not, remove all code and associated
        ///     build code above.
        SetLocalJson(GetModule(), "SCHEMA_VOCABULARIES", jVocabularies);
    }
}

json schema_GetVocabulary(int bForce = FALSE)
{
    json jSchema = GetLocalJson(GetModule(), "SCHEMA_VOCABULARY");
    if (jSchema == JsonNull() || bForce)
    {
        schema_BuildVocabulary(bForce);
        jSchema = GetLocalJson(GetModule(), "SCHEMA_VOCABULARY");
    }

    return jSchema;
}

int schema_vocabulary_HasKey(string sPath, json jKey, json joSchema = JSON_NULL)
{
    if (joSchema == JSON_NULL)
        joSchema = schema_GetVocabulary();

    return JsonFind(JsonPointer(joSchema, sPath), jKey) != JsonNull();
}

/// @brief Convenience function for schema_vocabulary_HasKey.
///     Determines if jKeyword exists in the properties path of
///     the meta schema.
/// @todo these convenience functions are primarly meant to be
///     used in the schema validation process as a quick check
///     to see if a keyword or def is present and, if not, skip
///     the validation process for that keyword or def.
int schema_vocabulary_HasKeywordJ(json jKeyword, json joSchema = JSON_NULL)
{
    return schema_vocabulary_HasKey("/properties", jKeyword, joSchema);
}

int schema_vocabulary_HasKeyword(string sKeyword, json joSchema = JSON_NULL)
{
    return schema_vocabulary_HasKeywordJ(JsonString(sKeyword), joSchema);
}

int schema_vocabulary_HasDefJ(json jDef, json joSchema = JSON_NULL)
{
    return schema_vocabulary_HasKey("/$defs", jDef, joSchema);
}

int schema_vocabulary_HasDef(string sDef, json joSchema = JSON_NULL)
{
    return schema_vocabulary_HasDefJ(JsonString(sDef), joSchema);
}

/// @todo Manual intitiator for the system.  Not really required
///     since all functions that need the schema will initialize it
///     on their own.  Primarily a convenience function for the dev
///     and will likely be removed upon distribution.
void schema_Initialize(int bForce = FALSE)
{
    schema_BuildVocabulary(bForce);
}

json schema_AnchorScopePush(json jaAnchorScope, string sAnchorName, json joAnchorNode)
{
    json joAnchorEntry = JsonObjectSet(JsonObject(), "name", JsonString(sAnchorName));
    joAnchorEntry = JsonObjectSet(joAnchorEntry, "node", joAnchorNode);

    if (JsonGetType(jaAnchorScope) != JSON_TYPE_ARRAY)
    {
        jaAnchorScope = JsonArray();
    }

    return JsonArrayInsert(jaAnchorScope, joAnchorEntry, 0);
}

json schema_AnchorScopePop(json jaAnchorScope, string sAnchorName)
{
    if (JsonGetType(jaAnchorScope) != JSON_TYPE_ARRAY)
    {
        return jaAnchorScope;
    }

    int i;
    for (i = 0; i < JsonGetLength(jaAnchorScope); i++)
    {
        json joAnchorEntry = JsonArrayGet(jaAnchorScope, i);
        if (JsonGetString(JsonObjectGet(joAnchorEntry, "name")) == sAnchorName)
        {
            jaAnchorScope = JsonArrayDel(jaAnchorScope, i);
            break;
        }
    }
    return jaAnchorScope;
}

json schema_AnchorScopeLookup(json jaAnchorScope, string sAnchorName)
{
    if (JsonGetType(jaAnchorScope) != JSON_TYPE_ARRAY)
    {
        return JsonNull();
    }

    int i;
    for (i = JsonGetLength(jaAnchorScope) - 1; i >= 0; i--)
    {
        json joAnchorEntry = JsonArrayGet(jaAnchorScope, i);
        if (JsonGetString(JsonObjectGet(joAnchorEntry, "name")) == sAnchorName)
        {
            return JsonObjectGet(joAnchorEntry, "node");
        }
    }
    return JsonNull();
}

// --- Error Reporting Utility ---

json schema_ResultAddError(json joResult, string sPointer, string sMessage)
{
    json jaErrors = JsonObjectGet(joResult, "errors");
    if (JsonGetType(jaErrors) != JSON_TYPE_ARRAY)
    {
        jaErrors = JsonArray();
    }

    json joError = JsonObject();
    joError = JsonObjectSet(joError, "pointer", JsonString(sPointer));
    joError = JsonObjectSet(joError, "message", JsonString(sMessage));

    jaErrors = JsonArrayInsert(jaErrors, joError, JsonGetLength(jaErrors));
    joResult = JsonObjectSet(joResult, "errors", jaErrors);
    return joResult;
}

// --- Utility for type matching ---
int schema_MatchesType(int instanceType, string expectedType)
{
    if (expectedType == "object")  return instanceType == JSON_TYPE_OBJECT;
    if (expectedType == "array")   return instanceType == JSON_TYPE_ARRAY;
    if (expectedType == "string")  return instanceType == JSON_TYPE_STRING;
    if (expectedType == "number")  return instanceType == JSON_TYPE_INTEGER || instanceType == JSON_TYPE_FLOAT;
    if (expectedType == "integer") return instanceType == JSON_TYPE_INTEGER;
    if (expectedType == "float")   return instanceType == JSON_TYPE_FLOAT;
    if (expectedType == "boolean") return instanceType == JSON_TYPE_BOOL;
    if (expectedType == "null")    return instanceType == JSON_TYPE_NULL;
    return 0;
}

// --- Per-keyword Validation Handlers ---

json schema_ValidateType(json joInstance, json joType, string sPointer, json joResult)
{
    int instanceType = JsonGetType(joInstance);

    if (JsonGetType(joType) == JSON_TYPE_STRING)
    {
        string expectedType = JsonGetString(joType);
        if (!schema_MatchesType(instanceType, expectedType))
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/type",
                "Type mismatch: expected " + expectedType + ".");
        }
    }
    else if (JsonGetType(joType) == JSON_TYPE_ARRAY)
    {
        int validType = 0;
        int j;
        for (j = 0; j < JsonGetLength(joType); j++)
        {
            string sType = JsonGetString(JsonArrayGet(joType, j));
            if (schema_MatchesType(instanceType, sType))
            {
                validType = 1;
                break;
            }
        }
        if (!validType)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/type",
                "Type mismatch: does not match any allowed types.");
        }
    }
    else if (JsonGetType(joType) != JSON_TYPE_NULL)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/type",
            "'type' must be a string or array of strings.");
    }
    return joResult;
}

json schema_ValidateEnum(json joInstance, json joEnum, string sPointer, json joResult)
{
    int valid = 0;
    if (JsonGetType(joEnum) == JSON_TYPE_ARRAY)
    {
        int i;
        for (i = 0; i < JsonGetLength(joEnum); i++)
        {
            if (JsonEquals(joInstance, JsonArrayGet(joEnum, i)))
            {
                valid = 1;
                break;
            }
        }
    }
    if (!valid)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/enum", "Value not in enum.");
    }
    return joResult;
}

json schema_ValidateConst(json joInstance, json joConst, string sPointer, json joResult)
{
    if (!JsonEquals(joInstance, joConst))
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/const", "Value does not match const.");
    }
    return joResult;
}

json schema_ValidateMultipleOf(json joInstance, json joMultipleOf, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joMultipleOf) == JSON_TYPE_INTEGER || JsonGetType(joMultipleOf) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float multipleOfValue = JsonGetFloat(joMultipleOf);
        if (multipleOfValue != 0.0 && fmod(instanceValue, multipleOfValue) != 0.0)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/multipleOf", "Value is not a multiple of " + JsonToString(joMultipleOf));
        }
    }
    return joResult;
}

json schema_ValidateMaximum(json joInstance, json joMaximum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joMaximum) == JSON_TYPE_INTEGER || JsonGetType(joMaximum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float maxValue = JsonGetFloat(joMaximum);
        if (instanceValue > maxValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maximum", "Value exceeds maximum " + JsonToString(joMaximum));
        }
    }
    return joResult;
}

json schema_ValidateMinimum(json joInstance, json joMinimum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joMinimum) == JSON_TYPE_INTEGER || JsonGetType(joMinimum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float minValue = JsonGetFloat(joMinimum);
        if (instanceValue < minValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minimum", "Value is below minimum " + JsonToString(joMinimum));
        }
    }
    return joResult;
}

json schema_ValidateExclusiveMaximum(json joInstance, json joExclusiveMaximum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joExclusiveMaximum) == JSON_TYPE_INTEGER || JsonGetType(joExclusiveMaximum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float maxValue = JsonGetFloat(joExclusiveMaximum);
        if (instanceValue >= maxValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMaximum", "Value must be less than " + JsonToString(joExclusiveMaximum));
        }
    }
    return joResult;
}

json schema_ValidateExclusiveMinimum(json joInstance, json joExclusiveMinimum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joExclusiveMinimum) == JSON_TYPE_INTEGER || JsonGetType(joExclusiveMinimum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float minValue = JsonGetFloat(joExclusiveMinimum);
        if (instanceValue <= minValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMinimum", "Value must be greater than " + JsonToString(joExclusiveMinimum));
        }
    }
    return joResult;
}

json schema_ValidateMaxLength(json joInstance, json joMaxLength, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_STRING && JsonGetType(joMaxLength) == JSON_TYPE_INTEGER)
    {
        int length = StringLen(JsonGetString(joInstance));
        int maxLength = JsonGetInt(joMaxLength);
        if (length > maxLength)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxLength", "String length exceeds maxLength " + IntToString(maxLength));
        }
    }
    return joResult;
}

json schema_ValidateMinLength(json joInstance, json joMinLength, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_STRING && JsonGetType(joMinLength) == JSON_TYPE_INTEGER)
    {
        int length = StringLen(JsonGetString(joInstance));
        int minLength = JsonGetInt(joMinLength);
        if (length < minLength)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minLength", "String length below minLength " + IntToString(minLength));
        }
    }
    return joResult;
}

json schema_ValidatePattern(json joInstance, json joPattern, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_STRING && JsonGetType(joPattern) == JSON_TYPE_STRING)
    {
        string str = JsonGetString(joInstance);
        string pattern = JsonGetString(joPattern);
        if (!RegexMatch(str, pattern))
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/pattern", "String does not match pattern: " + pattern);
        }
    }
    return joResult;
}

json schema_ValidateProperties(json joInstance, json joProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joProperties) == JSON_TYPE_OBJECT && JsonGetType(joInstance) == JSON_TYPE_OBJECT)
    {
        json jaPropKeys = JsonObjectKeys(joProperties);
        int j;
        for (j = 0; j < JsonGetLength(jaPropKeys); j++)
        {
            string sPropKey = JsonGetString(JsonArrayGet(jaPropKeys, j));
            json joSubschema = JsonObjectGet(joProperties, sPropKey);
            json joPropValue = JsonObjectGet(joInstance, sPropKey);
            if (JsonGetType(joSubschema) == JSON_TYPE_OBJECT)
            {
                joResult = schema_Validate(
                    joPropValue, joSubschema,
                    jaAnchorScope, jaDynamicAnchorScope,
                    sPointer + "/properties/" + sPropKey, joResult);
            }
        }
    }
    return joResult;
}

// --- Now fully implemented patternProperties ---
json schema_ValidatePatternProperties(json joInstance, json joPatternProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joPatternProperties) == JSON_TYPE_OBJECT)
    {
        json propNames = JsonObjectKeys(joInstance);
        json patterns = JsonObjectKeys(joPatternProperties);
        int i, j;
        for (i = 0; i < JsonGetLength(propNames); i++)
        {
            string propName = JsonGetString(JsonArrayGet(propNames, i));
            for (j = 0; j < JsonGetLength(patterns); j++)
            {
                string pattern = JsonGetString(JsonArrayGet(patterns, j));
                if (RegexMatch(propName, pattern))
                {
                    json propSchema = JsonObjectGet(joPatternProperties, pattern);
                    joResult = schema_Validate(
                        JsonObjectGet(joInstance, propName), propSchema,
                        jaAnchorScope, jaDynamicAnchorScope,
                        sPointer + "/patternProperties/" + pattern + "/" + propName, joResult
                    );
                }
            }
        }
    }
    return joResult;
}

// --- Now fully implemented additionalProperties ---
json schema_ValidateAdditionalProperties(json joInstance, json joAdditionalProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT)
    {
        json propNames = JsonObjectKeys(joInstance);
        json allowedNames = JsonObject();
        // Gather allowed names from "properties"
        if (JsonObjectHasKey(joAdditionalProperties, "properties"))
        {
            json properties = JsonObjectGet(joAdditionalProperties, "properties");
            if (JsonGetType(properties) == JSON_TYPE_OBJECT)
            {
                json keys = JsonObjectKeys(properties);
                int i;
                for (i = 0; i < JsonGetLength(keys); i++)
                {
                    allowedNames = JsonObjectSet(allowedNames, JsonGetString(JsonArrayGet(keys, i)), JsonBool(TRUE));
                }
            }
        }
        // Mark keys matched by patternProperties as allowed
        if (JsonObjectHasKey(joAdditionalProperties, "patternProperties"))
        {
            json patternProps = JsonObjectGet(joAdditionalProperties, "patternProperties");
            if (JsonGetType(patternProps) == JSON_TYPE_OBJECT)
            {
                json patterns = JsonObjectKeys(patternProps);
                int i, j;
                for (i = 0; i < JsonGetLength(propNames); i++)
                {
                    string propName = JsonGetString(JsonArrayGet(propNames, i));
                    for (j = 0; j < JsonGetLength(patterns); j++)
                    {
                        string pattern = JsonGetString(JsonArrayGet(patterns, j));
                        if (RegexMatch(propName, pattern))
                        {
                            allowedNames = JsonObjectSet(allowedNames, propName, JsonBool(TRUE));
                        }
                    }
                }
            }
        }
        // Now apply additionalProperties schema or boolean
        int i;
        for (i = 0; i < JsonGetLength(propNames); i++)
        {
            string propName = JsonGetString(JsonArrayGet(propNames, i));
            if (!JsonObjectHasKey(allowedNames, propName))
            {
                if (JsonGetType(joAdditionalProperties) == JSON_TYPE_BOOL && !JsonGetBool(joAdditionalProperties))
                {
                    joResult = schema_ResultAddError(joResult, sPointer + "/additionalProperties", "Property '" + propName + "' not allowed by additionalProperties:false");
                }
                else if (JsonGetType(joAdditionalProperties) == JSON_TYPE_OBJECT)
                {
                    joResult = schema_Validate(JsonObjectGet(joInstance, propName), joAdditionalProperties, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/additionalProperties/" + propName, joResult);
                }
            }
        }
    }
    return joResult;
}

// --- Now fully implemented propertyNames ---
json schema_ValidatePropertyNames(json joInstance, json joPropertyNames, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joPropertyNames) == JSON_TYPE_OBJECT)
    {
        json keys = JsonObjectKeys(joInstance);
        int i;
        for (i = 0; i < JsonGetLength(keys); i++)
        {
            string propName = JsonGetString(JsonArrayGet(keys, i));
            joResult = schema_Validate(JsonString(propName), joPropertyNames, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/propertyNames/" + propName, joResult);
        }
    }
    return joResult;
}

// --- Now fully implemented if/then/else ---
json schema_ValidateIf(json joInstance, json joIf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope, json joSchema)
{
    if (JsonGetType(joIf) == JSON_TYPE_OBJECT)
    {
        json tempResult = JsonObject();
        tempResult = schema_Validate(joInstance, joIf, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/if", tempResult);
        json errors = JsonObjectGet(tempResult, "errors");
        int passed = (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0);

        if (passed && JsonObjectHasKey(joSchema, "then"))
        {
            json joThen = JsonObjectGet(joSchema, "then");
            joResult = schema_Validate(joInstance, joThen, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/then", joResult);
        }
        else if (!passed && JsonObjectHasKey(joSchema, "else"))
        {
            json joElse = JsonObjectGet(joSchema, "else");
            joResult = schema_Validate(joInstance, joElse, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/else", joResult);
        }
    }
    return joResult;
}

// --- Remaining handlers as previously implemented (prefixItems, unevaluatedItems, unevaluatedProperties, etc.) ---

json schema_ValidatePrefixItems(json joInstance, json joPrefixItems, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joPrefixItems) == JSON_TYPE_ARRAY && JsonGetType(joInstance) == JSON_TYPE_ARRAY)
    {
        int schemaCount = JsonGetLength(joPrefixItems);
        int j;
        for (j = 0; j < schemaCount && j < JsonGetLength(joInstance); j++)
        {
            joResult = schema_Validate(
                JsonArrayGet(joInstance, j), JsonArrayGet(joPrefixItems, j),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/prefixItems/" + IntToString(j), joResult
            );
        }
    }
    return joResult;
}

json schema_ValidateAdditionalItems(json joInstance, json joAdditionalItems, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // Only relevant if "items" is an array (tuple validation)
    // If "additionalItems" is false, disallow extra elements
    // If it's a schema, validate extra elements with that schema
    // Implement as needed for your use case.
    return joResult;
}

json schema_ValidateUnevaluatedItems(json joInstance, json joUnevaluatedItems, json joSchema, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // NOTE: Full compliance requires tracking which items were already evaluated by "items"/"prefixItems"/"contains"
    // This is a simplified version that only checks items beyond prefixItems/items
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY)
    {
        int evaluated = 0;
        if (JsonObjectHasKey(joSchema, "prefixItems") && JsonGetType(JsonObjectGet(joSchema, "prefixItems")) == JSON_TYPE_ARRAY)
        {
            evaluated = JsonGetLength(JsonObjectGet(joSchema, "prefixItems"));
        }
        else if (JsonObjectHasKey(joSchema, "items") && JsonGetType(JsonObjectGet(joSchema, "items")) == JSON_TYPE_OBJECT)
        {
            evaluated = JsonGetLength(joInstance);
        }

        int i;
        for (i = evaluated; i < JsonGetLength(joInstance); i++)
        {
            if (JsonGetType(joUnevaluatedItems) == JSON_TYPE_BOOL && JsonGetBool(joUnevaluatedItems) == FALSE)
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedItems", "Item " + IntToString(i) + " is not allowed by unevaluatedItems:false");
            }
            else if (JsonGetType(joUnevaluatedItems) == JSON_TYPE_OBJECT)
            {
                joResult = schema_Validate(JsonArrayGet(joInstance, i), joUnevaluatedItems, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/unevaluatedItems/" + IntToString(i), joResult);
            }
        }
    }
    return joResult;
}

json schema_ValidateContains(json joInstance, json joContains, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joContains) == JSON_TYPE_OBJECT)
    {
        int found = 0;
        int j;
        for (j = 0; j < JsonGetLength(joInstance); j++)
        {
            json tempResult = JsonObject();
            tempResult = schema_Validate(JsonArrayGet(joInstance, j), joContains, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/contains", tempResult);
            json errors = JsonObjectGet(tempResult, "errors");
            if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
            {
                found = 1;
                break;
            }
        }
        if (!found)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/contains", "No array elements match 'contains' subschema.");
        }
    }
    return joResult;
}

json schema_ValidateMaxItems(json joInstance, json joMaxItems, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joMaxItems) == JSON_TYPE_INTEGER)
    {
        int length = JsonGetLength(joInstance);
        int maxItems = JsonGetInt(joMaxItems);
        if (length > maxItems)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxItems", "Array has more items than maxItems " + IntToString(maxItems));
        }
    }
    return joResult;
}

json schema_ValidateMinItems(json joInstance, json joMinItems, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joMinItems) == JSON_TYPE_INTEGER)
    {
        int length = JsonGetLength(joInstance);
        int minItems = JsonGetInt(joMinItems);
        if (length < minItems)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minItems", "Array has fewer items than minItems " + IntToString(minItems));
        }
    }
    return joResult;
}

json schema_ValidateUniqueItems(json joInstance, json joUniqueItems, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joUniqueItems) == JSON_TYPE_BOOL && JsonGetBool(joUniqueItems))
    {
        int length = JsonGetLength(joInstance);
        int i, j;
        for (i = 0; i < length; i++)
        {
            for (j = i + 1; j < length; j++)
            {
                if (JsonEquals(JsonArrayGet(joInstance, i), JsonArrayGet(joInstance, j)))
                {
                    joResult = schema_ResultAddError(joResult, sPointer + "/uniqueItems", "Array items are not unique.");
                    return joResult;
                }
            }
        }
    }
    return joResult;
}

json schema_ValidateMaxProperties(json joInstance, json joMaxProperties, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joMaxProperties) == JSON_TYPE_INTEGER)
    {
        int count = JsonGetLength(JsonObjectKeys(joInstance));
        int maxProps = JsonGetInt(joMaxProperties);
        if (count > maxProps)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxProperties", "Object has more properties than maxProperties " + IntToString(maxProps));
        }
    }
    return joResult;
}

json schema_ValidateMinProperties(json joInstance, json joMinProperties, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joMinProperties) == JSON_TYPE_INTEGER)
    {
        int count = JsonGetLength(JsonObjectKeys(joInstance));
        int minProps = JsonGetInt(joMinProperties);
        if (count < minProps)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minProperties", "Object has fewer properties than minProperties " + IntToString(minProps));
        }
    }
    return joResult;
}

json schema_ValidateRequired(json joInstance, json joRequired, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joRequired) == JSON_TYPE_ARRAY)
    {
        int i;
        for (i = 0; i < JsonGetLength(joRequired); i++)
        {
            string key = JsonGetString(JsonArrayGet(joRequired, i));
            if (!JsonObjectHasKey(joInstance, key))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/required", "Missing required property: " + key);
            }
        }
    }
    return joResult;
}

json schema_ValidateUnevaluatedProperties(json joInstance, json joUnevaluatedProperties, json joSchema, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // NOTE: Full compliance requires tracking evaluated properties.
    // This implementation considers all properties not in "properties" or matched by "patternProperties".
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT)
    {
        json evaluated = JsonObject();
        // Collect keys from "properties"
        if (JsonObjectHasKey(joSchema, "properties"))
        {
            json props = JsonObjectGet(joSchema, "properties");
            if (JsonGetType(props) == JSON_TYPE_OBJECT)
            {
                json keys = JsonObjectKeys(props);
                int i;
                for (i = 0; i < JsonGetLength(keys); i++)
                {
                    evaluated = JsonObjectSet(evaluated, JsonGetString(JsonArrayGet(keys, i)), JsonBool(TRUE));
                }
            }
        }
        // Collect keys matched by "patternProperties"
        if (JsonObjectHasKey(joSchema, "patternProperties"))
        {
            json pats = JsonObjectGet(joSchema, "patternProperties");
            if (JsonGetType(pats) == JSON_TYPE_OBJECT)
            {
                json instanceKeys = JsonObjectKeys(joInstance);
                int i, j;
                for (i = 0; i < JsonGetLength(instanceKeys); i++)
                {
                    string propName = JsonGetString(JsonArrayGet(instanceKeys, i));
                    json patKeys = JsonObjectKeys(pats);
                    for (j = 0; j < JsonGetLength(patKeys); j++)
                    {
                        string pat = JsonGetString(JsonArrayGet(patKeys, j));
                        if (RegexMatch(propName, pat))
                        {
                            evaluated = JsonObjectSet(evaluated, propName, JsonBool(TRUE));
                        }
                    }
                }
            }
        }
        // Now validate "unevaluatedProperties"
        json instanceKeys = JsonObjectKeys(joInstance);
        int i;
        for (i = 0; i < JsonGetLength(instanceKeys); i++)
        {
            string propName = JsonGetString(JsonArrayGet(instanceKeys, i));
            if (!JsonObjectHasKey(evaluated, propName))
            {
                if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_BOOL && JsonGetBool(joUnevaluatedProperties) == FALSE)
                {
                    joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedProperties", "Property " + propName + " not allowed by unevaluatedProperties:false");
                }
                else if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_OBJECT)
                {
                    joResult = schema_Validate(JsonObjectGet(joInstance, propName), joUnevaluatedProperties, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/unevaluatedProperties/" + propName, joResult);
                }
            }
        }
    }
    return joResult;
}

json schema_ValidateDependencies(json joInstance, json joDependencies, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // Deprecated in Draft 2019-09+. See dependentRequired and dependentSchemas.
    return joResult;
}

json schema_ValidateDependentRequired(json joInstance, json joDependentRequired, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joDependentRequired) == JSON_TYPE_OBJECT)
    {
        json keys = JsonObjectKeys(joDependentRequired);
        int i;
        for (i = 0; i < JsonGetLength(keys); i++)
        {
            string key = JsonGetString(JsonArrayGet(keys, i));
            if (JsonObjectHasKey(joInstance, key))
            {
                json requiredArr = JsonObjectGet(joDependentRequired, key);
                int j;
                for (j = 0; j < JsonGetLength(requiredArr); j++)
                {
                    string dep = JsonGetString(JsonArrayGet(requiredArr, j));
                    if (!JsonObjectHasKey(joInstance, dep))
                    {
                        joResult = schema_ResultAddError(joResult, sPointer + "/dependentRequired", "Property '" + key + "' requires property '" + dep + "'");
                    }
                }
            }
        }
    }
    return joResult;
}

json schema_ValidateDependentSchemas(json joInstance, json joDependentSchemas, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // Full implementation would iterate over dependencies and validate as needed.
    return joResult;
}

json schema_ValidateAllOf(json joInstance, json joAllOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joAllOf) == JSON_TYPE_ARRAY)
    {
        int i;
        for (i = 0; i < JsonGetLength(joAllOf); i++)
        {
            joResult = schema_Validate(
                joInstance, JsonArrayGet(joAllOf, i),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/allOf/" + IntToString(i), joResult
            );
        }
    }
    return joResult;
}

json schema_ValidateAnyOf(json joInstance, json joAnyOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joAnyOf) == JSON_TYPE_ARRAY)
    {
        int i, valid = 0;
        for (i = 0; i < JsonGetLength(joAnyOf); i++)
        {
            json tempResult = JsonObject();
            tempResult = schema_Validate(
                joInstance, JsonArrayGet(joAnyOf, i),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/anyOf/" + IntToString(i), tempResult
            );
            json errors = JsonObjectGet(tempResult, "errors");
            if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
            {
                valid = 1;
                break;
            }
        }
        if (!valid)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/anyOf", "Value does not match any schemas from 'anyOf'.");
        }
    }
    return joResult;
}

json schema_ValidateOneOf(json joInstance, json joOneOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joOneOf) == JSON_TYPE_ARRAY)
    {
        int i, matchCount = 0;
        for (i = 0; i < JsonGetLength(joOneOf); i++)
        {
            json tempResult = JsonObject();
            tempResult = schema_Validate(
                joInstance, JsonArrayGet(joOneOf, i),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/oneOf/" + IntToString(i), tempResult
            );
            json errors = JsonObjectGet(tempResult, "errors");
            if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
            {
                matchCount++;
            }
        }
        if (matchCount != 1)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/oneOf", "Value must match exactly one schema from 'oneOf'.");
        }
    }
    return joResult;
}

json schema_ValidateNot(json joInstance, json joNot, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joNot) == JSON_TYPE_OBJECT)
    {
        json tempResult = JsonObject();
        tempResult = schema_Validate(
            joInstance, joNot,
            jaAnchorScope, jaDynamicAnchorScope,
            sPointer + "/not", tempResult
        );
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/not", "Value must not be valid against 'not' schema.");
        }
    }
    return joResult;
}

json schema_ValidateFormat(json joInstance, json joFormat, string sPointer, json joResult)
{
    // Stub: For full support, implement 'format' checks for date, email, uri, etc.
    return joResult;
}

json schema_ValidateContentMediaType(json joInstance, json joContentMediaType, string sPointer, json joResult)
{
    // This is an annotation in the spec, not a validation assertion.
    // For completeness, do nothing.
    return joResult;
}

json schema_ValidateContentEncoding(json joInstance, json joContentEncoding, string sPointer, json joResult)
{
    // This is an annotation in the spec, not a validation assertion.
    // For completeness, do nothing.
    return joResult;
}

json schema_ValidateDefs(json joInstance, json joDefs, string sPointer, json joResult)
{
    // $defs is a schema organization tool, not a validation keyword.
    // No validation needed.
    return joResult;
}

json schema_ValidateUnknownKeyword(string sKey, json joInstance, json joValue, string sPointer, json joResult)
{
    // Unknown/custom keyword handler.
    return joResult;
}

// --- Main Instance/Schema Validation Function (Generic Keyword Dispatch) ---

json schema_Validate(
    json joInstance,
    json joSchema,
    json jaAnchorScope,
    json jaDynamicAnchorScope,
    string sPointer,
    json joResult
)
{
    // Track if we pushed an anchor/dynamicAnchor
    string sAnchorName = "";
    string sDynamicAnchorName = "";

    // --- Handle $anchor ---
    json jsAnchor = JsonObjectGet(joSchema, "$anchor");
    if (JsonGetType(jsAnchor) == JSON_TYPE_STRING)
    {
        sAnchorName = JsonGetString(jsAnchor);
        jaAnchorScope = schema_AnchorScopePush(jaAnchorScope, sAnchorName, joSchema);
    }

    // --- Handle $dynamicAnchor ---
    json jsDynamicAnchor = JsonObjectGet(joSchema, "$dynamicAnchor");
    if (JsonGetType(jsDynamicAnchor) == JSON_TYPE_STRING)
    {
        sDynamicAnchorName = JsonGetString(jsDynamicAnchor);
        jaDynamicAnchorScope = schema_AnchorScopePush(jaDynamicAnchorScope, sDynamicAnchorName, joSchema);
    }

    // --- Handle $ref ---
    json jsRef = JsonObjectGet(joSchema, "$ref");
    if (JsonGetType(jsRef) == JSON_TYPE_STRING)
    {
        string sRefName = jsRef;
        if (StringLeft(sRefName, 1) == "#")
        {
            sRefName = StringMid(sRefName, 1, StringLen(sRefName) - 1);
        }
        json joAnchorNode = schema_AnchorScopeLookup(jaAnchorScope, sRefName);
        if (JsonGetType(joAnchorNode) != JSON_TYPE_NULL)
        {
            joResult = schema_Validate(
                joInstance, joAnchorNode,
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/$ref", joResult);
        }
        else
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/$ref", "Unresolved $ref: " + jsRef);
        }
        // Pop anchor/dynamicAnchor if pushed
        if (sDynamicAnchorName != "")
        {
            jaDynamicAnchorScope = schema_AnchorScopePop(jaDynamicAnchorScope, sDynamicAnchorName);
        }
        if (sAnchorName != "")
        {
            jaAnchorScope = schema_AnchorScopePop(jaAnchorScope, sAnchorName);
        }
        return joResult;
    }

    // --- Handle $dynamicRef ---
    json jsDynamicRef = JsonObjectGet(joSchema, "$dynamicRef");
    if (JsonGetType(jsDynamicRef) == JSON_TYPE_STRING)
    {
        string sRefName = jsDynamicRef;
        if (StringLeft(sRefName, 1) == "#")
        {
            sRefName = StringMid(sRefName, 1, StringLen(sRefName) - 1);
        }
        json joDynamicAnchorNode = schema_AnchorScopeLookup(jaDynamicAnchorScope, sRefName);
        if (JsonGetType(joDynamicAnchorNode) != JSON_TYPE_NULL)
        {
            joResult = schema_Validate(
                joInstance, joDynamicAnchorNode,
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/$dynamicRef", joResult);
        }
        else
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/$dynamicRef", "Unresolved $dynamicRef: " + jsDynamicRef);
        }
        if (sDynamicAnchorName != "")
        {
            jaDynamicAnchorScope = schema_AnchorScopePop(jaDynamicAnchorScope, sDynamicAnchorName);
        }
        if (sAnchorName != "")
        {
            jaAnchorScope = schema_AnchorScopePop(jaAnchorScope, sAnchorName);
        }
        return joResult;
    }

    // --- Generic Keyword Dispatch ---
    json jaKeys = JsonObjectKeys(joSchema);
    int i;
    for (i = 0; i < JsonGetLength(jaKeys); i++)
    {
        string sKey = JsonGetString(JsonArrayGet(jaKeys, i));
        if (sKey == "$anchor" || sKey == "$ref" || sKey == "$dynamicAnchor" || sKey == "$dynamicRef")
            continue;

        json joValue = JsonObjectGet(joSchema, sKey);

        if      (sKey == "type")                joResult = schema_ValidateType(joInstance, joValue, sPointer, joResult);
        else if (sKey == "enum")                joResult = schema_ValidateEnum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "const")               joResult = schema_ValidateConst(joInstance, joValue, sPointer, joResult);
        else if (sKey == "multipleOf")          joResult = schema_ValidateMultipleOf(joInstance, joValue, sPointer, joResult);
        else if (sKey == "maximum")             joResult = schema_ValidateMaximum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minimum")             joResult = schema_ValidateMinimum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "exclusiveMaximum")    joResult = schema_ValidateExclusiveMaximum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "exclusiveMinimum")    joResult = schema_ValidateExclusiveMinimum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "maxLength")           joResult = schema_ValidateMaxLength(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minLength")           joResult = schema_ValidateMinLength(joInstance, joValue, sPointer, joResult);
        else if (sKey == "pattern")             joResult = schema_ValidatePattern(joInstance, joValue, sPointer, joResult);
        else if (sKey == "items")               joResult = schema_ValidateItems(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "prefixItems")         joResult = schema_ValidatePrefixItems(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "additionalItems")     joResult = schema_ValidateAdditionalItems(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "unevaluatedItems")    joResult = schema_ValidateUnevaluatedItems(joInstance, joValue, joSchema, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "contains")            joResult = schema_ValidateContains(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "maxItems")            joResult = schema_ValidateMaxItems(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minItems")            joResult = schema_ValidateMinItems(joInstance, joValue, sPointer, joResult);
        else if (sKey == "uniqueItems")         joResult = schema_ValidateUniqueItems(joInstance, joValue, sPointer, joResult);
        else if (sKey == "properties")          joResult = schema_ValidateProperties(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "patternProperties")   joResult = schema_ValidatePatternProperties(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "additionalProperties")joResult = schema_ValidateAdditionalProperties(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "required")            joResult = schema_ValidateRequired(joInstance, joValue, sPointer, joResult);
        else if (sKey == "propertyNames")       joResult = schema_ValidatePropertyNames(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "maxProperties")       joResult = schema_ValidateMaxProperties(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minProperties")       joResult = schema_ValidateMinProperties(joInstance, joValue, sPointer, joResult);
        else if (sKey == "unevaluatedProperties") joResult = schema_ValidateUnevaluatedProperties(joInstance, joValue, joSchema, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "dependencies")        joResult = schema_ValidateDependencies(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "dependentRequired")   joResult = schema_ValidateDependentRequired(joInstance, joValue, sPointer, joResult);
        else if (sKey == "dependentSchemas")    joResult = schema_ValidateDependentSchemas(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "if")                  joResult = schema_ValidateIf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope, joSchema);
        else if (sKey == "then") /* handled with if */ ;
        else if (sKey == "else") /* handled with if */ ;
        else if (sKey == "allOf")               joResult = schema_ValidateAllOf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "anyOf")               joResult = schema_ValidateAnyOf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "oneOf")               joResult = schema_ValidateOneOf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "not")                 joResult = schema_ValidateNot(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "format")              joResult = schema_ValidateFormat(joInstance, joValue, sPointer, joResult);
        else if (sKey == "contentMediaType")    joResult = schema_ValidateContentMediaType(joInstance, joValue, sPointer, joResult);
        else if (sKey == "contentEncoding")     joResult = schema_ValidateContentEncoding(joInstance, joValue, sPointer, joResult);
        else if (sKey == "$defs")               joResult = schema_ValidateDefs(joInstance, joValue, sPointer, joResult);
        else
            joResult = schema_ValidateUnknownKeyword(sKey, joInstance, joValue, sPointer, joResult);
    }

    // --- Pop anchor/dynamicAnchor if pushed ---
    if (sDynamicAnchorName != "")
    {
        jaDynamicAnchorScope = schema_AnchorScopePop(jaDynamicAnchorScope, sDynamicAnchorName);
    }
    if (sAnchorName != "")
    {
        jaAnchorScope = schema_AnchorScopePop(jaAnchorScope, sAnchorName);
    }

    return joResult;
}

///////////////////////////////////////////////////////
/////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////
///////////////////////////////////////////////////////

// --- Anchor Scope Stack Operations ---

json schema_AnchorScopePush(json jaAnchorScope, string sAnchorName, json joAnchorNode)
{
    json joAnchorEntry = JsonObjectSet(JsonObject(), "name", JsonString(sAnchorName));
    joAnchorEntry = JsonObjectSet(joAnchorEntry, "node", joAnchorNode);

    if (JsonGetType(jaAnchorScope) != JSON_TYPE_ARRAY)
    {
        jaAnchorScope = JsonArray();
    }

    return JsonArrayInsert(jaAnchorScope, joAnchorEntry, 0);
}

json schema_AnchorScopePop(json jaAnchorScope, string sAnchorName)
{
    if (JsonGetType(jaAnchorScope) != JSON_TYPE_ARRAY)
    {
        return jaAnchorScope;
    }

    int i;
    for (i = 0; i < JsonGetLength(jaAnchorScope); i++)
    {
        json joAnchorEntry = JsonArrayGet(jaAnchorScope, i);
        if (JsonGetString(JsonObjectGet(joAnchorEntry, "name")) == sAnchorName)
        {
            jaAnchorScope = JsonArrayRemove(jaAnchorScope, i);
            break;
        }
    }
    return jaAnchorScope;
}

json schema_AnchorScopeLookup(json jaAnchorScope, string sAnchorName)
{
    if (JsonGetType(jaAnchorScope) != JSON_TYPE_ARRAY)
    {
        return JsonNull();
    }

    int i;
    for (i = JsonGetLength(jaAnchorScope) - 1; i >= 0; i--)
    {
        json joAnchorEntry = JsonArrayGet(jaAnchorScope, i);
        if (JsonGetString(JsonObjectGet(joAnchorEntry, "name")) == sAnchorName)
        {
            return JsonObjectGet(joAnchorEntry, "node");
        }
    }
    return JsonNull();
}

// --- Error Reporting Utility ---

json schema_ResultAddError(json joResult, string sPointer, string sMessage)
{
    json jaErrors = JsonObjectGet(joResult, "errors");
    if (JsonGetType(jaErrors) != JSON_TYPE_ARRAY)
    {
        jaErrors = JsonArray();
    }

    json joError = JsonObject();
    joError = JsonObjectSet(joError, "pointer", JsonString(sPointer));
    joError = JsonObjectSet(joError, "message", JsonString(sMessage));

    jaErrors = JsonArrayInsert(jaErrors, joError, JsonGetLength(jaErrors));
    joResult = JsonObjectSet(joResult, "errors", jaErrors);
    return joResult;
}

// --- Utility for type matching ---
int schema_MatchesType(int instanceType, string expectedType)
{
    if (expectedType == "object")  return instanceType == JSON_TYPE_OBJECT;
    if (expectedType == "array")   return instanceType == JSON_TYPE_ARRAY;
    if (expectedType == "string")  return instanceType == JSON_TYPE_STRING;
    if (expectedType == "number")  return instanceType == JSON_TYPE_INTEGER || instanceType == JSON_TYPE_FLOAT;
    if (expectedType == "integer") return instanceType == JSON_TYPE_INTEGER;
    if (expectedType == "float")   return instanceType == JSON_TYPE_FLOAT;
    if (expectedType == "boolean") return instanceType == JSON_TYPE_BOOL;
    if (expectedType == "null")    return instanceType == JSON_TYPE_NULL;
    return 0;
}

// --- Per-keyword Validation Handlers ---

json schema_ValidateType(json joInstance, json joType, string sPointer, json joResult)
{
    int instanceType = JsonGetType(joInstance);

    if (JsonGetType(joType) == JSON_TYPE_STRING)
    {
        string expectedType = JsonGetString(joType);
        if (!schema_MatchesType(instanceType, expectedType))
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/type",
                "Type mismatch: expected " + expectedType + ".");
        }
    }
    else if (JsonGetType(joType) == JSON_TYPE_ARRAY)
    {
        int validType = 0;
        int j;
        for (j = 0; j < JsonGetLength(joType); j++)
        {
            string sType = JsonGetString(JsonArrayGet(joType, j));
            if (schema_MatchesType(instanceType, sType))
            {
                validType = 1;
                break;
            }
        }
        if (!validType)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/type",
                "Type mismatch: does not match any allowed types.");
        }
    }
    else if (JsonGetType(joType) != JSON_TYPE_NULL)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/type",
            "'type' must be a string or array of strings.");
    }
    return joResult;
}

json schema_ValidateEnum(json joInstance, json joEnum, string sPointer, json joResult)
{
    int valid = 0;
    if (JsonGetType(joEnum) == JSON_TYPE_ARRAY)
    {
        int i;
        for (i = 0; i < JsonGetLength(joEnum); i++)
        {
            if (JsonEquals(joInstance, JsonArrayGet(joEnum, i)))
            {
                valid = 1;
                break;
            }
        }
    }
    if (!valid)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/enum", "Value not in enum.");
    }
    return joResult;
}

json schema_ValidateConst(json joInstance, json joConst, string sPointer, json joResult)
{
    if (!JsonEquals(joInstance, joConst))
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/const", "Value does not match const.");
    }
    return joResult;
}

json schema_ValidateMultipleOf(json joInstance, json joMultipleOf, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joMultipleOf) == JSON_TYPE_INTEGER || JsonGetType(joMultipleOf) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float multipleOfValue = JsonGetFloat(joMultipleOf);
        if (multipleOfValue != 0.0 && fmod(instanceValue, multipleOfValue) != 0.0)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/multipleOf", "Value is not a multiple of " + JsonToString(joMultipleOf));
        }
    }
    return joResult;
}

json schema_ValidateMaximum(json joInstance, json joMaximum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joMaximum) == JSON_TYPE_INTEGER || JsonGetType(joMaximum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float maxValue = JsonGetFloat(joMaximum);
        if (instanceValue > maxValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maximum", "Value exceeds maximum " + JsonToString(joMaximum));
        }
    }
    return joResult;
}

json schema_ValidateMinimum(json joInstance, json joMinimum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joMinimum) == JSON_TYPE_INTEGER || JsonGetType(joMinimum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float minValue = JsonGetFloat(joMinimum);
        if (instanceValue < minValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minimum", "Value is below minimum " + JsonToString(joMinimum));
        }
    }
    return joResult;
}

json schema_ValidateExclusiveMaximum(json joInstance, json joExclusiveMaximum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joExclusiveMaximum) == JSON_TYPE_INTEGER || JsonGetType(joExclusiveMaximum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float maxValue = JsonGetFloat(joExclusiveMaximum);
        if (instanceValue >= maxValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMaximum", "Value must be less than " + JsonToString(joExclusiveMaximum));
        }
    }
    return joResult;
}

json schema_ValidateExclusiveMinimum(json joInstance, json joExclusiveMinimum, string sPointer, json joResult)
{
    if ((JsonGetType(joInstance) == JSON_TYPE_INTEGER || JsonGetType(joInstance) == JSON_TYPE_FLOAT) &&
        (JsonGetType(joExclusiveMinimum) == JSON_TYPE_INTEGER || JsonGetType(joExclusiveMinimum) == JSON_TYPE_FLOAT))
    {
        float instanceValue = JsonGetFloat(joInstance);
        float minValue = JsonGetFloat(joExclusiveMinimum);
        if (instanceValue <= minValue)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/exclusiveMinimum", "Value must be greater than " + JsonToString(joExclusiveMinimum));
        }
    }
    return joResult;
}

json schema_ValidateMaxLength(json joInstance, json joMaxLength, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_STRING && JsonGetType(joMaxLength) == JSON_TYPE_INTEGER)
    {
        int length = StringLen(JsonGetString(joInstance));
        int maxLength = JsonGetInt(joMaxLength);
        if (length > maxLength)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxLength", "String length exceeds maxLength " + IntToString(maxLength));
        }
    }
    return joResult;
}

json schema_ValidateMinLength(json joInstance, json joMinLength, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_STRING && JsonGetType(joMinLength) == JSON_TYPE_INTEGER)
    {
        int length = StringLen(JsonGetString(joInstance));
        int minLength = JsonGetInt(joMinLength);
        if (length < minLength)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minLength", "String length below minLength " + IntToString(minLength));
        }
    }
    return joResult;
}

json schema_ValidatePattern(json joInstance, json joPattern, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_STRING && JsonGetType(joPattern) == JSON_TYPE_STRING)
    {
        string str = JsonGetString(joInstance);
        string pattern = JsonGetString(joPattern);
        if (!RegexMatch(str, pattern))
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/pattern", "String does not match pattern: " + pattern);
        }
    }
    return joResult;
}

json schema_ValidateProperties(json joInstance, json joProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joProperties) == JSON_TYPE_OBJECT && JsonGetType(joInstance) == JSON_TYPE_OBJECT)
    {
        json jaPropKeys = JsonObjectKeys(joProperties);
        int j;
        for (j = 0; j < JsonGetLength(jaPropKeys); j++)
        {
            string sPropKey = JsonGetString(JsonArrayGet(jaPropKeys, j));
            json joSubschema = JsonObjectGet(joProperties, sPropKey);
            json joPropValue = JsonObjectGet(joInstance, sPropKey);
            if (JsonGetType(joSubschema) == JSON_TYPE_OBJECT)
            {
                joResult = schema_Validate(
                    joPropValue, joSubschema,
                    jaAnchorScope, jaDynamicAnchorScope,
                    sPointer + "/properties/" + sPropKey, joResult);
            }
        }
    }
    return joResult;
}

// --- Now fully implemented patternProperties ---
json schema_ValidatePatternProperties(json joInstance, json joPatternProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joPatternProperties) == JSON_TYPE_OBJECT)
    {
        json propNames = JsonObjectKeys(joInstance);
        json patterns = JsonObjectKeys(joPatternProperties);
        int i, j;
        for (i = 0; i < JsonGetLength(propNames); i++)
        {
            string propName = JsonGetString(JsonArrayGet(propNames, i));
            for (j = 0; j < JsonGetLength(patterns); j++)
            {
                string pattern = JsonGetString(JsonArrayGet(patterns, j));
                if (RegexMatch(propName, pattern))
                {
                    json propSchema = JsonObjectGet(joPatternProperties, pattern);
                    joResult = schema_Validate(
                        JsonObjectGet(joInstance, propName), propSchema,
                        jaAnchorScope, jaDynamicAnchorScope,
                        sPointer + "/patternProperties/" + pattern + "/" + propName, joResult
                    );
                }
            }
        }
    }
    return joResult;
}

// --- Now fully implemented additionalProperties ---
json schema_ValidateAdditionalProperties(json joInstance, json joAdditionalProperties, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT)
    {
        json propNames = JsonObjectKeys(joInstance);
        json allowedNames = JsonObject();
        // Gather allowed names from "properties"
        if (JsonObjectHasKey(joAdditionalProperties, "properties"))
        {
            json properties = JsonObjectGet(joAdditionalProperties, "properties");
            if (JsonGetType(properties) == JSON_TYPE_OBJECT)
            {
                json keys = JsonObjectKeys(properties);
                int i;
                for (i = 0; i < JsonGetLength(keys); i++)
                {
                    allowedNames = JsonObjectSet(allowedNames, JsonGetString(JsonArrayGet(keys, i)), JsonBool(TRUE));
                }
            }
        }
        // Mark keys matched by patternProperties as allowed
        if (JsonObjectHasKey(joAdditionalProperties, "patternProperties"))
        {
            json patternProps = JsonObjectGet(joAdditionalProperties, "patternProperties");
            if (JsonGetType(patternProps) == JSON_TYPE_OBJECT)
            {
                json patterns = JsonObjectKeys(patternProps);
                int i, j;
                for (i = 0; i < JsonGetLength(propNames); i++)
                {
                    string propName = JsonGetString(JsonArrayGet(propNames, i));
                    for (j = 0; j < JsonGetLength(patterns); j++)
                    {
                        string pattern = JsonGetString(JsonArrayGet(patterns, j));
                        if (RegexMatch(propName, pattern))
                        {
                            allowedNames = JsonObjectSet(allowedNames, propName, JsonBool(TRUE));
                        }
                    }
                }
            }
        }
        // Now apply additionalProperties schema or boolean
        int i;
        for (i = 0; i < JsonGetLength(propNames); i++)
        {
            string propName = JsonGetString(JsonArrayGet(propNames, i));
            if (!JsonObjectHasKey(allowedNames, propName))
            {
                if (JsonGetType(joAdditionalProperties) == JSON_TYPE_BOOL && !JsonGetBool(joAdditionalProperties))
                {
                    joResult = schema_ResultAddError(joResult, sPointer + "/additionalProperties", "Property '" + propName + "' not allowed by additionalProperties:false");
                }
                else if (JsonGetType(joAdditionalProperties) == JSON_TYPE_OBJECT)
                {
                    joResult = schema_Validate(JsonObjectGet(joInstance, propName), joAdditionalProperties, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/additionalProperties/" + propName, joResult);
                }
            }
        }
    }
    return joResult;
}

// --- Now fully implemented propertyNames ---
json schema_ValidatePropertyNames(json joInstance, json joPropertyNames, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joPropertyNames) == JSON_TYPE_OBJECT)
    {
        json keys = JsonObjectKeys(joInstance);
        int i;
        for (i = 0; i < JsonGetLength(keys); i++)
        {
            string propName = JsonGetString(JsonArrayGet(keys, i));
            joResult = schema_Validate(JsonString(propName), joPropertyNames, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/propertyNames/" + propName, joResult);
        }
    }
    return joResult;
}

// --- Now fully implemented if/then/else ---
json schema_ValidateIf(json joInstance, json joIf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope, json joSchema)
{
    if (JsonGetType(joIf) == JSON_TYPE_OBJECT)
    {
        json tempResult = JsonObject();
        tempResult = schema_Validate(joInstance, joIf, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/if", tempResult);
        json errors = JsonObjectGet(tempResult, "errors");
        int passed = (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0);

        if (passed && JsonObjectHasKey(joSchema, "then"))
        {
            json joThen = JsonObjectGet(joSchema, "then");
            joResult = schema_Validate(joInstance, joThen, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/then", joResult);
        }
        else if (!passed && JsonObjectHasKey(joSchema, "else"))
        {
            json joElse = JsonObjectGet(joSchema, "else");
            joResult = schema_Validate(joInstance, joElse, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/else", joResult);
        }
    }
    return joResult;
}

// --- Remaining handlers as previously implemented (prefixItems, unevaluatedItems, unevaluatedProperties, etc.) ---

json schema_ValidatePrefixItems(json joInstance, json joPrefixItems, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joPrefixItems) == JSON_TYPE_ARRAY && JsonGetType(joInstance) == JSON_TYPE_ARRAY)
    {
        int schemaCount = JsonGetLength(joPrefixItems);
        int j;
        for (j = 0; j < schemaCount && j < JsonGetLength(joInstance); j++)
        {
            joResult = schema_Validate(
                JsonArrayGet(joInstance, j), JsonArrayGet(joPrefixItems, j),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/prefixItems/" + IntToString(j), joResult
            );
        }
    }
    return joResult;
}

json schema_ValidateAdditionalItems(json joInstance, json joAdditionalItems, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // Only relevant if "items" is an array (tuple validation)
    // If "additionalItems" is false, disallow extra elements
    // If it's a schema, validate extra elements with that schema
    // Implement as needed for your use case.
    return joResult;
}

json schema_ValidateUnevaluatedItems(json joInstance, json joUnevaluatedItems, json joSchema, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // NOTE: Full compliance requires tracking which items were already evaluated by "items"/"prefixItems"/"contains"
    // This is a simplified version that only checks items beyond prefixItems/items
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY)
    {
        int evaluated = 0;
        if (JsonObjectHasKey(joSchema, "prefixItems") && JsonGetType(JsonObjectGet(joSchema, "prefixItems")) == JSON_TYPE_ARRAY)
        {
            evaluated = JsonGetLength(JsonObjectGet(joSchema, "prefixItems"));
        }
        else if (JsonObjectHasKey(joSchema, "items") && JsonGetType(JsonObjectGet(joSchema, "items")) == JSON_TYPE_OBJECT)
        {
            evaluated = JsonGetLength(joInstance);
        }

        int i;
        for (i = evaluated; i < JsonGetLength(joInstance); i++)
        {
            if (JsonGetType(joUnevaluatedItems) == JSON_TYPE_BOOL && JsonGetBool(joUnevaluatedItems) == FALSE)
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedItems", "Item " + IntToString(i) + " is not allowed by unevaluatedItems:false");
            }
            else if (JsonGetType(joUnevaluatedItems) == JSON_TYPE_OBJECT)
            {
                joResult = schema_Validate(JsonArrayGet(joInstance, i), joUnevaluatedItems, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/unevaluatedItems/" + IntToString(i), joResult);
            }
        }
    }
    return joResult;
}

json schema_ValidateContains(json joInstance, json joContains, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joContains) == JSON_TYPE_OBJECT)
    {
        int found = 0;
        int j;
        for (j = 0; j < JsonGetLength(joInstance); j++)
        {
            json tempResult = JsonObject();
            tempResult = schema_Validate(JsonArrayGet(joInstance, j), joContains, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/contains", tempResult);
            json errors = JsonObjectGet(tempResult, "errors");
            if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
            {
                found = 1;
                break;
            }
        }
        if (!found)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/contains", "No array elements match 'contains' subschema.");
        }
    }
    return joResult;
}

json schema_ValidateMaxItems(json joInstance, json joMaxItems, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joMaxItems) == JSON_TYPE_INTEGER)
    {
        int length = JsonGetLength(joInstance);
        int maxItems = JsonGetInt(joMaxItems);
        if (length > maxItems)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxItems", "Array has more items than maxItems " + IntToString(maxItems));
        }
    }
    return joResult;
}

json schema_ValidateMinItems(json joInstance, json joMinItems, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joMinItems) == JSON_TYPE_INTEGER)
    {
        int length = JsonGetLength(joInstance);
        int minItems = JsonGetInt(joMinItems);
        if (length < minItems)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minItems", "Array has fewer items than minItems " + IntToString(minItems));
        }
    }
    return joResult;
}

json schema_ValidateUniqueItems(json joInstance, json joUniqueItems, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_ARRAY && JsonGetType(joUniqueItems) == JSON_TYPE_BOOL && JsonGetBool(joUniqueItems))
    {
        int length = JsonGetLength(joInstance);
        int i, j;
        for (i = 0; i < length; i++)
        {
            for (j = i + 1; j < length; j++)
            {
                if (JsonEquals(JsonArrayGet(joInstance, i), JsonArrayGet(joInstance, j)))
                {
                    joResult = schema_ResultAddError(joResult, sPointer + "/uniqueItems", "Array items are not unique.");
                    return joResult;
                }
            }
        }
    }
    return joResult;
}

json schema_ValidateMaxProperties(json joInstance, json joMaxProperties, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joMaxProperties) == JSON_TYPE_INTEGER)
    {
        int count = JsonGetLength(JsonObjectKeys(joInstance));
        int maxProps = JsonGetInt(joMaxProperties);
        if (count > maxProps)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/maxProperties", "Object has more properties than maxProperties " + IntToString(maxProps));
        }
    }
    return joResult;
}

json schema_ValidateMinProperties(json joInstance, json joMinProperties, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joMinProperties) == JSON_TYPE_INTEGER)
    {
        int count = JsonGetLength(JsonObjectKeys(joInstance));
        int minProps = JsonGetInt(joMinProperties);
        if (count < minProps)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/minProperties", "Object has fewer properties than minProperties " + IntToString(minProps));
        }
    }
    return joResult;
}

json schema_ValidateRequired(json joInstance, json joRequired, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joRequired) == JSON_TYPE_ARRAY)
    {
        int i;
        for (i = 0; i < JsonGetLength(joRequired); i++)
        {
            string key = JsonGetString(JsonArrayGet(joRequired, i));
            if (!JsonObjectHasKey(joInstance, key))
            {
                joResult = schema_ResultAddError(joResult, sPointer + "/required", "Missing required property: " + key);
            }
        }
    }
    return joResult;
}

json schema_ValidateUnevaluatedProperties(json joInstance, json joUnevaluatedProperties, json joSchema, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // NOTE: Full compliance requires tracking evaluated properties.
    // This implementation considers all properties not in "properties" or matched by "patternProperties".
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT)
    {
        json evaluated = JsonObject();
        // Collect keys from "properties"
        if (JsonObjectHasKey(joSchema, "properties"))
        {
            json props = JsonObjectGet(joSchema, "properties");
            if (JsonGetType(props) == JSON_TYPE_OBJECT)
            {
                json keys = JsonObjectKeys(props);
                int i;
                for (i = 0; i < JsonGetLength(keys); i++)
                {
                    evaluated = JsonObjectSet(evaluated, JsonGetString(JsonArrayGet(keys, i)), JsonBool(TRUE));
                }
            }
        }
        // Collect keys matched by "patternProperties"
        if (JsonObjectHasKey(joSchema, "patternProperties"))
        {
            json pats = JsonObjectGet(joSchema, "patternProperties");
            if (JsonGetType(pats) == JSON_TYPE_OBJECT)
            {
                json instanceKeys = JsonObjectKeys(joInstance);
                int i, j;
                for (i = 0; i < JsonGetLength(instanceKeys); i++)
                {
                    string propName = JsonGetString(JsonArrayGet(instanceKeys, i));
                    json patKeys = JsonObjectKeys(pats);
                    for (j = 0; j < JsonGetLength(patKeys); j++)
                    {
                        string pat = JsonGetString(JsonArrayGet(patKeys, j));
                        if (RegexMatch(propName, pat))
                        {
                            evaluated = JsonObjectSet(evaluated, propName, JsonBool(TRUE));
                        }
                    }
                }
            }
        }
        // Now validate "unevaluatedProperties"
        json instanceKeys = JsonObjectKeys(joInstance);
        int i;
        for (i = 0; i < JsonGetLength(instanceKeys); i++)
        {
            string propName = JsonGetString(JsonArrayGet(instanceKeys, i));
            if (!JsonObjectHasKey(evaluated, propName))
            {
                if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_BOOL && JsonGetBool(joUnevaluatedProperties) == FALSE)
                {
                    joResult = schema_ResultAddError(joResult, sPointer + "/unevaluatedProperties", "Property " + propName + " not allowed by unevaluatedProperties:false");
                }
                else if (JsonGetType(joUnevaluatedProperties) == JSON_TYPE_OBJECT)
                {
                    joResult = schema_Validate(JsonObjectGet(joInstance, propName), joUnevaluatedProperties, jaAnchorScope, jaDynamicAnchorScope, sPointer + "/unevaluatedProperties/" + propName, joResult);
                }
            }
        }
    }
    return joResult;
}

json schema_ValidateDependencies(json joInstance, json joDependencies, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // Deprecated in Draft 2019-09+. See dependentRequired and dependentSchemas.
    return joResult;
}

json schema_ValidateDependentRequired(json joInstance, json joDependentRequired, string sPointer, json joResult)
{
    if (JsonGetType(joInstance) == JSON_TYPE_OBJECT && JsonGetType(joDependentRequired) == JSON_TYPE_OBJECT)
    {
        json keys = JsonObjectKeys(joDependentRequired);
        int i;
        for (i = 0; i < JsonGetLength(keys); i++)
        {
            string key = JsonGetString(JsonArrayGet(keys, i));
            if (JsonObjectHasKey(joInstance, key))
            {
                json requiredArr = JsonObjectGet(joDependentRequired, key);
                int j;
                for (j = 0; j < JsonGetLength(requiredArr); j++)
                {
                    string dep = JsonGetString(JsonArrayGet(requiredArr, j));
                    if (!JsonObjectHasKey(joInstance, dep))
                    {
                        joResult = schema_ResultAddError(joResult, sPointer + "/dependentRequired", "Property '" + key + "' requires property '" + dep + "'");
                    }
                }
            }
        }
    }
    return joResult;
}

json schema_ValidateDependentSchemas(json joInstance, json joDependentSchemas, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    // Full implementation would iterate over dependencies and validate as needed.
    return joResult;
}

json schema_ValidateAllOf(json joInstance, json joAllOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joAllOf) == JSON_TYPE_ARRAY)
    {
        int i;
        for (i = 0; i < JsonGetLength(joAllOf); i++)
        {
            joResult = schema_Validate(
                joInstance, JsonArrayGet(joAllOf, i),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/allOf/" + IntToString(i), joResult
            );
        }
    }
    return joResult;
}

json schema_ValidateAnyOf(json joInstance, json joAnyOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joAnyOf) == JSON_TYPE_ARRAY)
    {
        int i, valid = 0;
        for (i = 0; i < JsonGetLength(joAnyOf); i++)
        {
            json tempResult = JsonObject();
            tempResult = schema_Validate(
                joInstance, JsonArrayGet(joAnyOf, i),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/anyOf/" + IntToString(i), tempResult
            );
            json errors = JsonObjectGet(tempResult, "errors");
            if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
            {
                valid = 1;
                break;
            }
        }
        if (!valid)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/anyOf", "Value does not match any schemas from 'anyOf'.");
        }
    }
    return joResult;
}

json schema_ValidateOneOf(json joInstance, json joOneOf, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joOneOf) == JSON_TYPE_ARRAY)
    {
        int i, matchCount = 0;
        for (i = 0; i < JsonGetLength(joOneOf); i++)
        {
            json tempResult = JsonObject();
            tempResult = schema_Validate(
                joInstance, JsonArrayGet(joOneOf, i),
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/oneOf/" + IntToString(i), tempResult
            );
            json errors = JsonObjectGet(tempResult, "errors");
            if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
            {
                matchCount++;
            }
        }
        if (matchCount != 1)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/oneOf", "Value must match exactly one schema from 'oneOf'.");
        }
    }
    return joResult;
}

json schema_ValidateNot(json joInstance, json joNot, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joNot) == JSON_TYPE_OBJECT)
    {
        json tempResult = JsonObject();
        tempResult = schema_Validate(
            joInstance, joNot,
            jaAnchorScope, jaDynamicAnchorScope,
            sPointer + "/not", tempResult
        );
        json errors = JsonObjectGet(tempResult, "errors");
        if (JsonGetType(errors) != JSON_TYPE_ARRAY || JsonGetLength(errors) == 0)
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/not", "Value must not be valid against 'not' schema.");
        }
    }
    return joResult;
}

json schema_ValidateFormat(json joInstance, json joFormat, string sPointer, json joResult)
{
    // Stub: For full support, implement 'format' checks for date, email, uri, etc.
    return joResult;
}

json schema_ValidateContentMediaType(json joInstance, json joContentMediaType, string sPointer, json joResult)
{
    // This is an annotation in the spec, not a validation assertion.
    // For completeness, do nothing.
    return joResult;
}

json schema_ValidateContentEncoding(json joInstance, json joContentEncoding, string sPointer, json joResult)
{
    // This is an annotation in the spec, not a validation assertion.
    // For completeness, do nothing.
    return joResult;
}

json schema_ValidateDefs(json joInstance, json joDefs, string sPointer, json joResult)
{
    // $defs is a schema organization tool, not a validation keyword.
    // No validation needed.
    return joResult;
}

json schema_ValidateUnknownKeyword(string sKey, json joInstance, json joValue, string sPointer, json joResult)
{
    // Unknown/custom keyword handler.
    return joResult;
}

// --- Main Instance/Schema Validation Function (Generic Keyword Dispatch) ---

json schema_Validate(
    json joInstance,
    json joSchema,
    json jaAnchorScope,
    json jaDynamicAnchorScope,
    string sPointer,
    json joResult
)
{
    // Track if we pushed an anchor/dynamicAnchor
    string sAnchorName = "";
    string sDynamicAnchorName = "";

    // --- Handle $anchor ---
    json jsAnchor = JsonObjectGet(joSchema, "$anchor");
    if (JsonGetType(jsAnchor) == JSON_TYPE_STRING)
    {
        sAnchorName = JsonGetString(jsAnchor);
        jaAnchorScope = schema_AnchorScopePush(jaAnchorScope, sAnchorName, joSchema);
    }

    // --- Handle $dynamicAnchor ---
    json jsDynamicAnchor = JsonObjectGet(joSchema, "$dynamicAnchor");
    if (JsonGetType(jsDynamicAnchor) == JSON_TYPE_STRING)
    {
        sDynamicAnchorName = JsonGetString(jsDynamicAnchor);
        jaDynamicAnchorScope = schema_AnchorScopePush(jaDynamicAnchorScope, sDynamicAnchorName, joSchema);
    }

    // --- Handle $ref ---
    json jsRef = JsonObjectGet(joSchema, "$ref");
    if (JsonGetType(jsRef) == JSON_TYPE_STRING)
    {
        string sRefName = jsRef;
        if (StringLeft(sRefName, 1) == "#")
        {
            sRefName = StringMid(sRefName, 1, StringLen(sRefName) - 1);
        }
        json joAnchorNode = schema_AnchorScopeLookup(jaAnchorScope, sRefName);
        if (JsonGetType(joAnchorNode) != JSON_TYPE_NULL)
        {
            joResult = schema_Validate(
                joInstance, joAnchorNode,
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/$ref", joResult);
        }
        else
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/$ref", "Unresolved $ref: " + jsRef);
        }
        // Pop anchor/dynamicAnchor if pushed
        if (sDynamicAnchorName != "")
        {
            jaDynamicAnchorScope = schema_AnchorScopePop(jaDynamicAnchorScope, sDynamicAnchorName);
        }
        if (sAnchorName != "")
        {
            jaAnchorScope = schema_AnchorScopePop(jaAnchorScope, sAnchorName);
        }
        return joResult;
    }

    // --- Handle $dynamicRef ---
    json jsDynamicRef = JsonObjectGet(joSchema, "$dynamicRef");
    if (JsonGetType(jsDynamicRef) == JSON_TYPE_STRING)
    {
        string sRefName = jsDynamicRef;
        if (StringLeft(sRefName, 1) == "#")
        {
            sRefName = StringMid(sRefName, 1, StringLen(sRefName) - 1);
        }
        json joDynamicAnchorNode = schema_AnchorScopeLookup(jaDynamicAnchorScope, sRefName);
        if (JsonGetType(joDynamicAnchorNode) != JSON_TYPE_NULL)
        {
            joResult = schema_Validate(
                joInstance, joDynamicAnchorNode,
                jaAnchorScope, jaDynamicAnchorScope,
                sPointer + "/$dynamicRef", joResult);
        }
        else
        {
            joResult = schema_ResultAddError(joResult, sPointer + "/$dynamicRef", "Unresolved $dynamicRef: " + jsDynamicRef);
        }
        if (sDynamicAnchorName != "")
        {
            jaDynamicAnchorScope = schema_AnchorScopePop(jaDynamicAnchorScope, sDynamicAnchorName);
        }
        if (sAnchorName != "")
        {
            jaAnchorScope = schema_AnchorScopePop(jaAnchorScope, sAnchorName);
        }
        return joResult;
    }

    // --- Generic Keyword Dispatch ---
    json jaKeys = JsonObjectKeys(joSchema);
    int i;
    for (i = 0; i < JsonGetLength(jaKeys); i++)
    {
        string sKey = JsonGetString(JsonArrayGet(jaKeys, i));
        if (sKey == "$anchor" || sKey == "$ref" || sKey == "$dynamicAnchor" || sKey == "$dynamicRef")
            continue;

        json joValue = JsonObjectGet(joSchema, sKey);

        if      (sKey == "type")                joResult = schema_ValidateType(joInstance, joValue, sPointer, joResult);
        else if (sKey == "enum")                joResult = schema_ValidateEnum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "const")               joResult = schema_ValidateConst(joInstance, joValue, sPointer, joResult);
        else if (sKey == "multipleOf")          joResult = schema_ValidateMultipleOf(joInstance, joValue, sPointer, joResult);
        else if (sKey == "maximum")             joResult = schema_ValidateMaximum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minimum")             joResult = schema_ValidateMinimum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "exclusiveMaximum")    joResult = schema_ValidateExclusiveMaximum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "exclusiveMinimum")    joResult = schema_ValidateExclusiveMinimum(joInstance, joValue, sPointer, joResult);
        else if (sKey == "maxLength")           joResult = schema_ValidateMaxLength(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minLength")           joResult = schema_ValidateMinLength(joInstance, joValue, sPointer, joResult);
        else if (sKey == "pattern")             joResult = schema_ValidatePattern(joInstance, joValue, sPointer, joResult);
        else if (sKey == "items")               joResult = schema_ValidateItems(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "prefixItems")         joResult = schema_ValidatePrefixItems(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "additionalItems")     joResult = schema_ValidateAdditionalItems(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "unevaluatedItems")    joResult = schema_ValidateUnevaluatedItems(joInstance, joValue, joSchema, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "contains")            joResult = schema_ValidateContains(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "maxItems")            joResult = schema_ValidateMaxItems(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minItems")            joResult = schema_ValidateMinItems(joInstance, joValue, sPointer, joResult);
        else if (sKey == "uniqueItems")         joResult = schema_ValidateUniqueItems(joInstance, joValue, sPointer, joResult);
        else if (sKey == "properties")          joResult = schema_ValidateProperties(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "patternProperties")   joResult = schema_ValidatePatternProperties(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "additionalProperties")joResult = schema_ValidateAdditionalProperties(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "required")            joResult = schema_ValidateRequired(joInstance, joValue, sPointer, joResult);
        else if (sKey == "propertyNames")       joResult = schema_ValidatePropertyNames(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "maxProperties")       joResult = schema_ValidateMaxProperties(joInstance, joValue, sPointer, joResult);
        else if (sKey == "minProperties")       joResult = schema_ValidateMinProperties(joInstance, joValue, sPointer, joResult);
        else if (sKey == "unevaluatedProperties") joResult = schema_ValidateUnevaluatedProperties(joInstance, joValue, joSchema, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "dependencies")        joResult = schema_ValidateDependencies(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "dependentRequired")   joResult = schema_ValidateDependentRequired(joInstance, joValue, sPointer, joResult);
        else if (sKey == "dependentSchemas")    joResult = schema_ValidateDependentSchemas(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "if")                  joResult = schema_ValidateIf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope, joSchema);
        else if (sKey == "then") /* handled with if */ ;
        else if (sKey == "else") /* handled with if */ ;
        else if (sKey == "allOf")               joResult = schema_ValidateAllOf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "anyOf")               joResult = schema_ValidateAnyOf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "oneOf")               joResult = schema_ValidateOneOf(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "not")                 joResult = schema_ValidateNot(joInstance, joValue, sPointer, joResult, jaAnchorScope, jaDynamicAnchorScope);
        else if (sKey == "format")              joResult = schema_ValidateFormat(joInstance, joValue, sPointer, joResult);
        else if (sKey == "contentMediaType")    joResult = schema_ValidateContentMediaType(joInstance, joValue, sPointer, joResult);
        else if (sKey == "contentEncoding")     joResult = schema_ValidateContentEncoding(joInstance, joValue, sPointer, joResult);
        else if (sKey == "$defs")               joResult = schema_ValidateDefs(joInstance, joValue, sPointer, joResult);
        else
            joResult = schema_ValidateUnknownKeyword(sKey, joInstance, joValue, sPointer, joResult);
    }

    // --- Pop anchor/dynamicAnchor if pushed ---
    if (sDynamicAnchorName != "")
    {
        jaDynamicAnchorScope = schema_AnchorScopePop(jaDynamicAnchorScope, sDynamicAnchorName);
    }
    if (sAnchorName != "")
    {
        jaAnchorScope = schema_AnchorScopePop(jaAnchorScope, sAnchorName);
    }

    return joResult;
}