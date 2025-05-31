// --- Content Vocabulary Handlers ---

// contentEncoding: must be a string if present in schema
json schema_ValidateContentEncoding(json joInstance, json joContentEncoding, string sPointer, json joResult)
{
    if (JsonGetType(joContentEncoding) != JSON_TYPE_STRING)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/contentEncoding", "contentEncoding must be a string.");
    }
    // Annotation only for instance validation
    return joResult;
}

// contentMediaType: must be a string if present in schema
json schema_ValidateContentMediaType(json joInstance, json joContentMediaType, string sPointer, json joResult)
{
    if (JsonGetType(joContentMediaType) != JSON_TYPE_STRING)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/contentMediaType", "contentMediaType must be a string.");
    }
    // Annotation only for instance validation
    return joResult;
}

// contentSchema: must be an object if present in schema
json schema_ValidateContentSchema(json joInstance, json joContentSchema, string sPointer, json joResult, json jaAnchorScope, json jaDynamicAnchorScope)
{
    if (JsonGetType(joContentSchema) != JSON_TYPE_OBJECT)
    {
        joResult = schema_ResultAddError(joResult, sPointer + "/contentSchema", "contentSchema must be an object.");
        return joResult;
    }
    // If the schema is valid, do content validation as before:
    // (Your previous implementation for instance validation goes here.)
    // ...
    return joResult;
}