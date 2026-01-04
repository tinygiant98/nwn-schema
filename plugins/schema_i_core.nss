
#include "util_i_debug"
#include "schema_i_debug"

const int SCHEMA_DRAFT_4 = 1;
const int SCHEMA_DRAFT_6 = 2;
const int SCHEMA_DRAFT_7 = 3;
const int SCHEMA_DRAFT_2019_09 = 4;
const int SCHEMA_DRAFT_2020_12 = 5;
const int SCHEMA_DRAFT_LATEST = SCHEMA_DRAFT_2020_12;

/// @note This default metaschema draft will be used anytime a user provide a custom
///     schema to be validated and has not provided a valid $schema key (either the
///     key was not included or doesn't exist within the schema database).
const string SCHEMA_DEFAULT_DRAFT = "https://json-schema.org/draft/2020-12/schema";
const string SCHEMA_DEFAULT_OUTPUT = "https://json-schema.org/draft/2020-12/output/schema";

const string SCHEMA_DB_SYSTEM = "schema_system";

/// @todo
///     [ ] debugging stuff, remove if able, or make prettier
int SOURCE=TRUE;

json joScopes = JsonParse(r"{
    ""SCHEMA_SCOPE_CONTEXT"": [],
    ""SCHEMA_SCOPE_DYNAMIC"": [],
    ""SCHEMA_SCOPE_INSTANCEPATH"": [],
    ""SCHEMA_SCOPE_LEXICAL"": [],
    ""SCHEMA_SCOPE_SCHEMA"": """",
    ""SCHEMA_SCOPE_SCHEMAPATH"": [],
    ""SCHEMA_SCOPE_KEYMAP"": []
}");

json jaContextKeys = JsonParse(r"[
    ""SCHEMA_CONTEXT_EVALUATED_PROPERTIES"",
    ""SCHEMA_CONTEXT_EVALUATED_ITEMS""
]");

/// @todo
///     [ ] Is there a way to remove these prototypes so they don't show up in the toolset editor?
///         [ ] schema_reference_ -> schema_core_ ? since it's used in a lot of places?
json schema_core_Validate(json jInstance, json joSchema);
json schema_reference_GetSchema(string sSchemaID);
json schema_Load(json joSchema, string sDefaultDraft = "", json joOverlay = JSON_NULL);
json schema_Validate(json jInstance, string sSchemaID);
json schema_ValidateObject(json jInstance, json joSchema, string sDefaultDraft = "");

// Forward declarations for utility functions used in reference resolution
json schema_util_JsonObjectGet(json jObject, string sKey);
int schema_util_HasKey(json jObject, string sKey);
int schema_util_RegExpMatch(string sPattern, string sString);

sqlquery schema_core_PrepareQuery(string s, int bForceModule = FALSE);
string schema_reference_MergePath(json jaMatchBase, string sPathRef);

string schema_reference_NormalizePath(string sPath);

/// @private Escape a string for use in a JSON pointer (~ -> ~0, / -> ~1)
string schema_reference_EscapePointer(string sToken)
{
    if (sToken == "") return "";
    
    string s = "SELECT replace(replace(:token, '~', '~0'), '/', '~1')";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":token", sToken);
    
    return SqlStep(q) ? SqlGetString(q, 0) : sToken;
}

/// @private Unescape a JSON pointer string (~1 -> /, ~0 -> ~)
string schema_reference_UnescapePointer(string sPointer)
{
    if (sPointer == "") return "";

    string sQuery = "SELECT replace(replace(:pointer, '~1', '/'), '~0', '~')";
    sqlquery q = schema_core_PrepareQuery(sQuery);
    SqlBindString(q, ":pointer", sPointer);
    
    return SqlStep(q) ? SqlGetString(q, 0) : sPointer;
}

/// @private Decode a URI string (e.g. %25 -> %, %2F -> /)
/// @note This implementation uses SQLite to handle proper UTF-8 byte decoding.
string schema_reference_DecodeURI(string sURI)
{
    if (FindSubString(sURI, "%") == -1)
        return sURI;

    // 1. Get the hex representation of the URI string
    string sQuery = "SELECT hex(:uri)";
    sqlquery q = schema_core_PrepareQuery(sQuery);
    SqlBindString(q, ":uri", sURI);
    
    if (!SqlStep(q)) return sURI;
    string sHex = SqlGetString(q, 0);
    string sResultHex = "";
    int i, nLen = GetStringLength(sHex);

    // 2. Parse the hex string
    for (i = 0; i < nLen; i += 2)
    {
        string sByte = GetSubString(sHex, i, 2);
        if (sByte == "25" && i + 6 <= nLen) // Found '%' (25) and have at least 2 more chars (4 hex digits)
        {
            string sH1 = GetSubString(sHex, i + 2, 2); // e.g. 43 ('C')
            string sH2 = GetSubString(sHex, i + 4, 2); // e.g. 33 ('3')
            
            // Convert hex codes back to characters using JSON parsing
            string sC1 = JsonGetString(JsonParse("\"\\u00" + sH1 + "\""));
            string sC2 = JsonGetString(JsonParse("\"\\u00" + sH2 + "\""));
            
            sResultHex += sC1 + sC2;
            i += 4; // Skip the 2 encoded bytes (4 hex chars)
        }
        else
        {
            sResultHex += sByte;
        }
    }
    
    // 3. Cast the final hex string back to text
    sQuery = "SELECT CAST(x'" + sResultHex + "' AS TEXT)";
    q = schema_core_PrepareQuery(sQuery);
    
    return SqlStep(q) ? SqlGetString(q, 0) : sURI;
}

/// @private Prepare a query for any schema-related database or for module use.
/// @param s The query string to prepare.
/// @param bForceModule If TRUE, the query is prepared for the module database.
sqlquery schema_core_PrepareQuery(string s, int bForceModule = FALSE)
{
    if (bForceModule)
        return SqlPrepareQueryObject(GetModule(), s);
    else
        return SqlPrepareQueryCampaign(SCHEMA_DB_SYSTEM, s);
}

void schema_core_ExecuteQuery(string s, int bForceModule = FALSE)
{
    SqlStep(schema_core_PrepareQuery(s, bForceModule));
}

void schema_core_BeginTransaction(int bForceModule = FALSE)
{
    schema_core_ExecuteQuery("BEGIN TRANSACTION;", bForceModule);
}

void schema_core_CommitTransaction(int bForceModule = FALSE)
{
    schema_core_ExecuteQuery("COMMIT TRANSACTION;", bForceModule);
}

void schema_core_CreateTables()
{
    schema_core_BeginTransaction(); 

    /// `schema_schema` holds all validated schema, including meta schema provided by json-schema.org
    ///     All user-provided schema will also be saved to this table for retrieval or later use.
    ///     If the UNIQUE key is violated, the record will be removed and replaced (not updated) by
    ///     the incoming schema, allowing associated records in `schema_keyword` to be deleted without
    ///     using a foreign key.
    string s = r"
        CREATE TABLE IF NOT EXISTS schema_schema (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            schema TEXT NOT NULL,
            schema_id TEXT GENERATED ALWAYS AS (
                COALESCE(
                    json_extract(schema, '$.$id'),
                    json_extract(schema, '$.id')
                )
            ) STORED,
            schema_schema TEXT GENERATED ALWAYS AS (json_extract(schema, '$.$schema')) STORED,
            schema_title TEXT GENERATED ALWAYS AS (json_extract(schema, '$.title')) STORED,
            schema_description TEXT GENERATED ALWAYS AS (json_extract(schema, '$.description')) STORED,
            UNIQUE(schema_id) ON CONFLICT REPLACE
        );
    ";
    schema_core_ExecuteQuery(s);

    s = r"
        CREATE INDEX IF NOT EXISTS schema_index ON schema_schema (schema_id);
    ;";
    schema_core_ExecuteQuery(s);

    /// `schema_keyword` holds all keywords directly assocaited with a specified schema.
    ///     Keywords associated by reference (or allOf) are not included here and will
    ///     be resolved when keyword map is loaded at validation runtime.
    s = r"
        CREATE TABLE IF NOT EXISTS schema_keyword (
            schema_id INTEGER,
            keyword TEXT,
            PRIMARY KEY (schema_id, keyword)
        ) WITHOUT ROWID;
    ";
    schema_core_ExecuteQuery(s);

    /// @note This trigger is the basis for the keyword mapping and validation system.
    ///     When a new schema is inserted, all keywords from its properties object
    ///     are inserted into the `schema_keyword` table for later use during validation.
    s = r"
        CREATE TRIGGER IF NOT EXISTS schema_insert_keywords AFTER INSERT ON schema_schema
        BEGIN
            INSERT INTO schema_keyword (schema_id, keyword)
            SELECT new.id, key
            FROM json_each(json_extract(new.schema, '$.properties'));
        END;
    ";
    schema_core_ExecuteQuery(s);

    /// @note Foreign Key relationships don't always work as expected because of the way
    ///     NWN handles sqlite connections to external databases.  To get around this limitation,
    ///     use a BEFORE INSERT trigger to remove all associated records in other tables
    ///     and remove all use of FOREIGN KEY.
    s = r"
        CREATE TRIGGER IF NOT EXISTS schema_delete_keywords BEFORE INSERT ON schema_schema
        FOR EACH ROW
        BEGIN
            DELETE FROM schema_keyword 
            WHERE schema_id = (SELECT id FROM schema_schema WHERE schema_id = NEW.schema_id);
        END;
    ";
    schema_core_ExecuteQuery(s);
    schema_core_CommitTransaction();
}

void schema_output_SaveValidationResult(json joResult)
{
    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joResult);
}

json schema_output_GetValidationResult()
{
    return GetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT");
}

/// -----------------------------------------------------------------------------------------------
///                                         SCOPE MANAGEMENT
/// -----------------------------------------------------------------------------------------------

/// @brief Scope management is accomplished via local variables set on the module object.  Scope
///     arrays track the various data required for each validation recursion, including the ability
///     to track unique data for concurrent validation attempts.  Scope arrays are simulated-base-1,
///     in that the first array entry is an empty json value, except for the lexical scope variable
///     in which the index-0 value is used to store the full validation schema for use during
///     $ref resolution.
///
///        The depth value is used to track concurrent validation attempts, which occur when
///     the system finds a valid schema in a location that cannot be consider validated, such as from
///     a file.  If the desired schema is found in a file, the system will attempt to validate the
///     provided schema before continuing with the instance validation.

/// @private Destroy all scope-related local variables to ensure scope data from multiple
///     validation attempts do not collide.
void schema_scope_Destroy()
{
    DelayCommand(0.01, DeleteLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT"));
    DelayCommand(0.01, DeleteLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH"));

    json jaScopes = JsonObjectKeys(joScopes);
    int i; for (; i < JsonGetLength(jaScopes); i++)
        DelayCommand(0.01, DeleteLocalJson(GetModule(), JsonGetString(JsonArrayGet(jaScopes, i))));
}

/// @private Resize scope arrays to match the current scope depth.  If the array must grow,
///     new members are initialized to the default values in joScopes.
void schema_scope_ResizeArrays()
{
    int nRequiredLength = GetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH") + 1;

    json jaScopes = JsonObjectKeys(joScopes);
    int i; for (; i < JsonGetLength(jaScopes); i++)
    {
        string sScope = JsonGetString(JsonArrayGet(jaScopes, i));
        
        json joScope = GetLocalJson(GetModule(), sScope);
        if (JsonGetType(joScope) != JSON_TYPE_ARRAY)
            joScope = JsonArray();        
        
        int nLength = JsonGetLength(joScope);
        if (nLength == nRequiredLength)
            continue;
        else if (nLength > nRequiredLength)
            joScope = JsonArrayGetRange(joScope, 0, nRequiredLength);
        else if (nLength < nRequiredLength)
        {
            while (JsonGetLength(joScope) < nRequiredLength)
                joScope = JsonArrayInsert(joScope, JsonObjectGet(joScopes, sScope));
        }

        SetLocalJson(GetModule(), sScope, joScope);
    }
}

/// @private Retrieve the current scope depth.
/// @returns The current scope depth, base 1.
/// @note This will rarely be greater than one, however, this value will increment
///     if nested validations are initiated, such as referencing a schema that
///     has not been previously validated.
int schema_scope_GetDepth()
{
    int nDepth = GetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH");
    if (nDepth == 0)
    {
        SetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH", ++nDepth);
        schema_scope_ResizeArrays();
    }

    return nDepth;
}

/// @private Push a new item into the specified scope array at the current depth.
/// @param sScope Scope type SCHEMA_SCOPE_*; must be an array of arrays.
/// @param jItem The json object to push into the array.
void schema_scope_PushArrayItem(string sScope, json jItem, int nIndex = -1)
{
    int nDepth = schema_scope_GetDepth();
    json jaScopes = GetLocalJson(GetModule(), sScope);

    if (JsonGetType(jaScopes) != JSON_TYPE_ARRAY)
        return;

    json jaScope = JsonArrayGet(jaScopes, nDepth);
    if (JsonGetType(jaScope) != JSON_TYPE_ARRAY)
        return;

    if (nIndex == -1)
        jaScopes = JsonArraySet(jaScopes, nDepth, JsonArrayInsert(jaScope, jItem));
    else if (nIndex >= 0)
        jaScopes = JsonArraySet(jaScopes, nDepth, JsonArraySet(jaScope, nIndex, jItem));

    SetLocalJson(GetModule(), sScope, jaScopes);
}

/// @private Push a new item into the specified scope array at the current depth.
/// @param sScope Scope type SCHEMA_SCOPE_*; must be a simple array.
/// @param jItem The json object to push into the array.
void schema_scope_PushItem(string sScope, json jItem)
{
    json jaScope = GetLocalJson(GetModule(), sScope);
    if (JsonGetType(jaScope) != JSON_TYPE_ARRAY)
        return;

    SetLocalJson(GetModule(), sScope, JsonArraySet(jaScope, schema_scope_GetDepth(), jItem));
}

/// @private Get the current scope data for the specified scope type.
/// @param sScope Scope type SCHEMA_SCOPE_*.
/// @returns A json array containing the data for the current scope depth.
/// @note This function will normally not be called directly.  Use convenience functions
///     defined below to ensure correct access to scope data.
json schema_scope_Get(string sScope)
{
    int nDepth = schema_scope_GetDepth();
    json jaScopes = GetLocalJson(GetModule(), sScope);

    if (JsonGetType(jaScopes) != JSON_TYPE_ARRAY || JsonGetLength(jaScopes) <= nDepth)
        return JsonArray();
    
    return JsonArrayGet(jaScopes, nDepth);
}

/// @private Convenience functions to retrieve scope data at the current depth.
json schema_scope_GetDynamic()      {return schema_scope_Get("SCHEMA_SCOPE_DYNAMIC");}
json schema_scope_GetLexical()      {return schema_scope_Get("SCHEMA_SCOPE_LEXICAL");}
json schema_scope_GetSchema()       {return schema_scope_Get("SCHEMA_SCOPE_SCHEMA");}
json schema_scope_GetSchemaPath()   {return schema_scope_Get("SCHEMA_SCOPE_SCHEMAPATH");}
json schema_scope_GetInstancePath() {return schema_scope_Get("SCHEMA_SCOPE_INSTANCEPATH");}
json schema_scope_GetKeymap()       {return schema_scope_Get("SCHEMA_SCOPE_KEYMAP");}

/// @private Retrieve the context data for a context key at the current depth.
/// @param sContextKey SCHEMA_CONTEXT_*.
/// @note Context data is used to transfer context (annotation data access) between
///     validations.  This will be used in applicators that run multiple subsequent
///     validations, such as `allOf`, where subsequent validations require access
///     to the annotation data from previous validations.
json schema_scope_GetContext(string sContextKey)
{
    string sScopeKey = "SCHEMA_SCOPE_CONTEXT";

    json jIndex = JsonFind(jaContextKeys, JsonString(sContextKey));
    if (JsonGetType(jIndex) == JSON_TYPE_NULL)
        return JsonArray();

    json jaContext = schema_scope_Get(sScopeKey);
    if (JsonGetLength(jaContext) < JsonGetLength(jaContextKeys))
    {
        while (JsonGetLength(jaContext) < JsonGetLength(jaContextKeys))
            jaContext = JsonArrayInsert(jaContext, JsonObjectGet(joScopes, sScopeKey));

        schema_scope_PushArrayItem(sScopeKey, jaContext);
    }

    return JsonArrayGet(jaContext, JsonGetInt(jIndex));
}

/// @private Deconstruct a pointer string into an array of pointer segments.
/// @param sPointer The pointer string to deconstruct.
/// @returns A json array containing the path segments, or an empty json array if the path is empty.
json schema_scope_Deconstruct(string sPointer)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sPointer", JsonString(sPointer));

    // Remove leading # if present
    if (GetStringLeft(sPointer, 1) == "#")
        sPointer = GetStringRight(sPointer, GetStringLength(sPointer) - 1);

    if (sPointer == "")
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return JsonArray();
    }

    // If it starts with /, remove it to simplify splitting, but keep track that we did
    if (GetStringLeft(sPointer, 1) == "/")
        sPointer = GetStringRight(sPointer, GetStringLength(sPointer) - 1);
    else
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return JsonArray(); // JSON Pointer must start with / if not empty
    }

    string s = r"
        WITH RECURSIVE split(value, str) AS (
            SELECT 
                '', :str || '/'
            UNION ALL
            SELECT
                substr(str, 0, instr(str, '/')),
                substr(str, instr(str, '/') + 1)
            FROM split
            WHERE str != ''
        )
        SELECT json_group_array(value) FROM split WHERE str != :str || '/';
    ";
    
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":str", sPointer);

    schema_debug_ExitFunction(__FUNCTION__);
    return SqlStep(q) ? SqlGetJson(q, 0) : JsonArray();
}

/// @private Construct a pointer string from a json array of pointer segments.
/// @param jaPointer The json array containing the pointer segments.
/// @returns A string representing the pointer, or an empty string if the input is null or empty.
string schema_scope_Construct(json jaPointer = JSON_NULL)
{
    if (JsonGetType(jaPointer) != JSON_TYPE_ARRAY || JsonGetLength(jaPointer) == 0)
        return "";

    string sPath;
   
    int i; for (; i < JsonGetLength(jaPointer); i++)
    {
        string sPart = JsonGetString(JsonArrayGet(jaPointer, i));
        sPath += "/" + schema_reference_EscapePointer(sPart);
    }
    
    return sPath;
}

/// @private Convenience function to construct pointer from lexical scope members.
string schema_scope_ConstructSchemaPath()   {return schema_scope_Construct(schema_scope_GetSchemaPath());}
string schema_scope_ConstructInstancePath() {return schema_scope_Construct(schema_scope_GetInstancePath());}

/// @private Convenience functions to modify scope arrays.
void schema_scope_PushLexical(json joScope)      {schema_scope_PushArrayItem("SCHEMA_SCOPE_LEXICAL", joScope);}
void schema_scope_PushDynamic(json joScope)      {schema_scope_PushArrayItem("SCHEMA_SCOPE_DYNAMIC", joScope);}
void schema_scope_PushSchemaPath(string sPath)   {schema_scope_PushArrayItem("SCHEMA_SCOPE_SCHEMAPATH", JsonString(sPath));}
void schema_scope_PushInstancePath(string sPath) {schema_scope_PushArrayItem("SCHEMA_SCOPE_INSTANCEPATH", JsonString(sPath));}
void schema_scope_PushKeymap(json jaScope)       {schema_scope_PushArrayItem("SCHEMA_SCOPE_KEYMAP", jaScope);}

/// @private Merge two json arrays into a single array, removing duplicates and sorting
///     the resultant array from least to greatest.
/// @param jA The first json array to merge.
/// @param jB The second json array to merge.
/// @note Any json types can be included in `jA` and `jB`.
json schema_scope_MergeArrays(json jA, json jB)
{
    if (JsonGetType(jA) != JSON_TYPE_ARRAY || JsonGetType(jB) != JSON_TYPE_ARRAY)
        return JsonArray();

    string s = r"
        SELECT json_group_array(value)
        FROM (
            SELECT DISTINCT value
            FROM (
                SELECT value FROM json_each(:a)
                UNION ALL
                SELECT value FROM json_each(:b)
            )
            ORDER BY value
        );
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":a", jA);
    SqlBindJson(q, ":b", jB);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonArray();
}

void schema_scope_PushContext(string sContextKey, json jaContext)
{
    string sScopeKey = "SCHEMA_SCOPE_CONTEXT";

    json jIndex = JsonFind(jaContextKeys, JsonString(sContextKey));
    if (JsonGetType(jIndex) == JSON_TYPE_NULL)
        return;

    json jaContexts = schema_scope_Get(sScopeKey);
    while (JsonGetLength(jaContexts) < JsonGetLength(jaContextKeys))
        jaContexts = JsonArrayInsert(jaContexts, JsonObjectGet(joScopes, sScopeKey));

    json jaContextItem = JsonArrayGet(jaContexts, JsonGetInt(jIndex));
    if (JsonGetLength(jaContextItem) > 0)
        jaContext = schema_scope_MergeArrays(jaContextItem, jaContext);

    jaContexts = JsonArraySet(jaContexts, JsonGetInt(jIndex), jaContext);
    schema_scope_PushArrayItem(sScopeKey, jaContexts);
}

/// @private Push a schema into the schema scope array.  If the schema is a known
///     json-schema.org draft, store the schema as its SCHEMA_DRAFT_* integer value.
/// @param sSchema The schema $id to push into the schema scope array.
void schema_scope_PushSchema(string sSchema)
{
    if (sSchema == "")
        return;

    string r = "^https?:\\/\\/json-schema\\.org\\/draft[-\\/](\\d*-?\\d*)\\/schema#?$";
    string sDraft = JsonGetString(JsonArrayGet(RegExpMatch(r, sSchema), 1));

    json jSchema;
    if      (sDraft == "04")      jSchema = JsonInt(SCHEMA_DRAFT_4);
    else if (sDraft == "06")      jSchema = JsonInt(SCHEMA_DRAFT_6);
    else if (sDraft == "07")      jSchema = JsonInt(SCHEMA_DRAFT_7);
    else if (sDraft == "2019-09") jSchema = JsonInt(SCHEMA_DRAFT_2019_09);
    else if (sDraft == "2020-12") jSchema = JsonInt(SCHEMA_DRAFT_2020_12);
    else                          jSchema = JsonString(sSchema);

    schema_scope_PushItem("SCHEMA_SCOPE_SCHEMA", jSchema);
}

/// @brief Remove the last member of a scope array ensuring the array length
///     matches current scope depth.
/// @param sScope Scope type; SCHEMA_SCOPE_*
void schema_scope_Pop(string sScope)
{
    int nDepth = schema_scope_GetDepth();

    json jaPaths = GetLocalJson(GetModule(), sScope);
    if (JsonGetType(jaPaths) != JSON_TYPE_ARRAY || JsonGetLength(jaPaths) <= nDepth)
        return;

    json jaPath = JsonArrayGet(jaPaths, nDepth);
    if (JsonGetType(jaPath) != JSON_TYPE_ARRAY)
        return;

    int nLength = JsonGetLength(jaPath);
    if (nLength == 1)
        jaPaths = JsonArraySet(jaPaths, nDepth, JsonArray());
    else if (nLength > 1)
        jaPaths = JsonArraySet(jaPaths, nDepth, JsonArrayGetRange(jaPath, 0, nLength - 2));
    
    SetLocalJson(GetModule(), sScope, jaPaths);
}

/// @private Convenience functions to pop the last member from scope arrays.
void schema_scope_PopLexical()      {schema_scope_Pop("SCHEMA_SCOPE_LEXICAL");}
void schema_scope_PopDynamic()      {schema_scope_Pop("SCHEMA_SCOPE_DYNAMIC");}
void schema_scope_PopSchema()       {schema_scope_Pop("SCHEMA_SCOPE_SCHEMA");}
void schema_scope_PopSchemaPath()   {schema_scope_Pop("SCHEMA_SCOPE_SCHEMAPATH");}
void schema_scope_PopInstancePath() {schema_scope_Pop("SCHEMA_SCOPE_INSTANCEPATH");}
void schema_scope_PopKeymap()       {schema_scope_Pop("SCHEMA_SCOPE_KEYMAP");}

void schema_scope_PopContext()
{
    string sScopeKey = "SCHEMA_SCOPE_CONTEXT";

    json jaContext = JsonArray();
    while (JsonGetLength(jaContext) < JsonGetLength(jaContextKeys))
        jaContext = JsonArrayInsert(jaContext, JsonObjectGet(joScopes, sScopeKey));

    schema_scope_PushArrayItem(sScopeKey, jaContext);
}

void schema_scope_ReplaceSchemaPath(string sPath)
{
    schema_scope_PopSchemaPath();
    schema_scope_PushSchemaPath(sPath);
}

void schema_scope_ReplaceInstancePath(string sPath)
{
    schema_scope_PopInstancePath();
    schema_scope_PushInstancePath(sPath);
}

void schema_scope_SetBaseSchema(json joSchema)
{
    schema_scope_PushLexical(joSchema);
}

json schema_scope_GetBaseSchema()
{
    json jaScope = schema_scope_Get("SCHEMA_SCOPE_LEXICAL");
    int nLen = JsonGetLength(jaScope);
    if (nLen == 0) return JsonNull();
    return JsonArrayGet(jaScope, nLen - 1);
}

/// @private Resolve a relative URI against a base URI.
string schema_reference_ResolveURI(string sBaseURI, string sRelativeURI)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sBaseURI", JsonString(sBaseURI));
    schema_debug_Argument(__FUNCTION__, "sRelativeURI", JsonString(sRelativeURI));

    if (sRelativeURI == "" || sRelativeURI == "#")
    {
        schema_debug_Message("sRelativeURI is empty or #");
        schema_debug_ExitFunction(__FUNCTION__);
        return sBaseURI;
    }

    // Regex for URI parsing (RFC 3986)
    string r = "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?$";
    json jaMatchRef = RegExpMatch(r, sRelativeURI);
    
    // If relative URI is absolute (has scheme), return it
    if (JsonGetString(JsonArrayGet(jaMatchRef, 2)) != "")
    {
        schema_debug_Message("sRealtiveURI has a schema; returning");
        schema_debug_ExitFunction(__FUNCTION__);
        return sRelativeURI;
    }

    json jaMatchBase = RegExpMatch(r, sBaseURI);
    string sTargetURI = "";

    if (JsonGetString(JsonArrayGet(jaMatchRef, 3)) != "") // Authority (//...)
    {
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 1)); // Scheme
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 3)); // Authority
        sTargetURI += schema_reference_NormalizePath(JsonGetString(JsonArrayGet(jaMatchRef, 5))); // Path
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6)); // Query
    }
    else
    {
        if (JsonGetString(JsonArrayGet(jaMatchRef, 5)) == "") // Empty Path
        {
            sTargetURI += JsonGetString(JsonArrayGet(jaMatchBase, 5)); // Base Path
            if (JsonGetString(JsonArrayGet(jaMatchRef, 6)) != "")
                sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6)); // Ref Query
            else
                sTargetURI += JsonGetString(JsonArrayGet(jaMatchBase, 6)); // Base Query
        }
        else
        {
            if (GetStringLeft(JsonGetString(JsonArrayGet(jaMatchRef, 5)), 1) == "/") // Absolute Path
                sTargetURI += schema_reference_NormalizePath(JsonGetString(JsonArrayGet(jaMatchRef, 5)));
            else 
            {
                // Merge Paths
                string sMerged = schema_reference_MergePath(jaMatchBase, JsonGetString(JsonArrayGet(jaMatchRef, 5)));
                sTargetURI += sMerged;
                sTargetURI = schema_reference_NormalizePath(sTargetURI);
            }
            sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6)); // Query
        }
        sTargetURI = JsonGetString(JsonArrayGet(jaMatchBase, 3)) + sTargetURI; // Authority
        sTargetURI = JsonGetString(JsonArrayGet(jaMatchBase, 1)) + sTargetURI; // Scheme
    }
    
    sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 8)); // Fragment
    schema_debug_ExitFunction(__FUNCTION__);
    return sTargetURI;
}

/// @private Increment the current scope depth by 1 and modify the scope arrays to handle
///     the additional depth.
void schema_scope_IncrementDepth()
{
    SetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH", schema_scope_GetDepth() + 1);
    schema_scope_ResizeArrays();
}

/// @private Decrement the current scope depth by 1 and resize the scope arrays to match
///     the new depth.
/// @note If the depth is already at 1, no changes are made.
void schema_scope_DecrementDepth()
{
    int nDepth = schema_scope_GetDepth();
    if (nDepth > 1)
    {
        SetLocalInt(GetModule(), "SCHEMA_SCOPE_DEPTH", --nDepth);
        schema_scope_ResizeArrays();
    }
}

/// -----------------------------------------------------------------------------------------------
///                                         OUTPUT MANAGEMENT
/// -----------------------------------------------------------------------------------------------

/// @brief Output management functions provide functionality to recursively build the verbose
///    output of schema validation, as defined by json-schema.org.  This includes full validity,
///    error and annotations for each json object in the instance.  Functions are provided to pare
///    down the output to the user's desired verbosity level.

const string SCHEMA_OUTPUT_BASIC = "basic";
const string SCHEMA_OUTPUT_DETAILED = "detailed";
const string SCHEMA_OUTPUT_FLAG = "flag";
const string SCHEMA_OUTPUT_VERBOSE = "verbose";

string schema_output_GetErrorMessage(string sError, string sData = "")
{
    if (GetStringLeft(sError, 1) != "<")
        sError = "<validate_" + sError + ">";

    if (sError == "<validate_type>")
        return "instance does not match type";
    else if (sError == "<validate_enum>")
        return "instance not found in ";
    else if (sError == "<validate_minlength>")
        return "instance is shorter than minLength";
    else if (sError == "<validate_maxlength>")
        return "instance is longer than maxLength";
    else if (sError == "<validate_pattern>")
        return "instance does not match pattern";
    else if (sError == "<validate_minimum>")
        return "instance is less than minimum";
    else if (sError == "<validate_exclusiveminimum>")
        return "instance is not greater than exclusiveMinimum";
    else if (sError == "<validate_maximum>")
        return "instance is greater than maximum";
    else if (sError == "<validate_exlusivemaximum")
        return "instance is not less than exclusiveMaximum";
    else if (sError == "<validate_multipleof>")
        return "instance is not a multiple of multipleOf";
    else if (sError == "<validate_minitems>")
        return "instance length is less than minItems";
    else if (sError == "<validate_maxitems>")
        return "instance length is greater than maxItems";
    else if (sError == "<validate_uniqueitems>")
        return "instance items are not unique";
    else if (sError == "<validate_prefixitems>")
        return "<@todo>";
    else if (sError == "<validate_items>")
        return "<@todo>";
    else if (sError == "<validate_contains>")
        return "<@todo>";
    else if (sError == "<validate_mincontains")
        return "instace contains less than minContains";
    else if (sError == "<validate_maxcontains>")
        return "instance contains more than maxContains";
    else if (sError == "<validate_unevaluateditems>")
        return "<@todo>";
    else if (sError == "<validate_required>")
        return "instance missing required properties";
    else if (sError == "validate_minproperties>")
        return "instance has less than minProperties";
    else if (sError == "validate_maxproperties>")
        return "instance has more than maxProperties";
    else if (sError == "<validate_dependentrequired>")
        return "instance missing dependent property";
    else if (sError == "<validate_properties>")
        return "<@todo>";
    else if (sError == "<validate_patternproperties>")
        return "<@todo>";
    else if (sError == "<validate_additionalproperties>")
        return "<@todo>";
    else if (sError == "<validate_dependentschemas>")
        return "<@todo>";
    else if (sError == "<validate_propertynames>")
        return "instance property names do not match schema";
    else if (sError == "<validate_unevaluatedproperties>")
        return "<@todo>";
    else if (sError == "<validate_not>")
        return "instance matches not schema";
    else if (sError == "<validate_allof>")
        return "instance does not match all allOf schemas";
    else if (sError == "<validate_anyof>")
        return "instance does not match any anyOf schemas";
    else if (sError == "<validate_oneof>")
        return "instance does not match exactly one oneOf schema";
    else if (sError == "<validate_then>")
        return "instance valid against if but fails then";
    else if (sError == "<validate_else>")
        return "instance invalid against if but fails else";    
    else if (sError == "<validate_never>")
        return "instance never valid";
    
    else if (sError == "<instance_string>")
        return "instance must be a string";
    else if (sError == "<instance_number>")
        return "instance must be a number";
    else if (sError == "<instance_array>")
        return "instance must be an array";
    else if (sError == "<instance_object>")
        return "instance must be an object";
    
    return "";
}

int schema_output_GetValid(json joOutputUnit)
{
    return (JsonObjectGet(joOutputUnit, "valid") == JSON_TRUE);
}

json schema_output_SetValid(json joOutputUnit, int bValid = TRUE)
{
    return JsonObjectSet(joOutputUnit, "valid", bValid ? JSON_TRUE : JSON_FALSE);
}

/// @private Build a minimally acceptable output object for the desired verbosity level.  This
///     output object will not include any optional fields.  It relies on the json-schema.org
///     suggested validation output schema for draft 2020-12.  This schema must be packed in the
///     module file (or otherwise found by resman through the /development or other folder), and
///     can be downloaded from https://json-schema.org/draft/2020-12/output/schema.  The default
///     filename is output.txt, but can be any other valid filename if passed to the sFile argument.
/// @param sVerbosity The desired verbosity level: SCHEMA_OUTPUT_*
/// @param sFile The .txt file containing the output schema.
/// @returns A valid json object containing the minimal key:value pairs as defined by the output
///     schema at the desired verbosity level.  If no 'required' properties are found, an empty
///     json object is returned as this empty object has all 'required' properties and meets all
///     schema requirements.
/// @warning Although technically possible to replace this recommended output schema from json-schema.org
///     with a different schema, the replacement schema must conform to the general structure of
///     the json-schema.org output schema, including the use of the 'anyOf' keyword to handle
///     various verbosity levels, and the 'required' keyword to determine which key:value pairs
///     are minimally necessary.
/// @note This function is called constantly, therefore the results of the function are saved into
///     a local database for quicker retrieval.  Users that wish to reset the data, for events such
///     as metaschema updates, may reset all saved results using schema_core_Reset().
json schema_output_GetMinimalObject(string sVerbosity = SCHEMA_OUTPUT_VERBOSE, string sSchemaID = "")
{
    if (sVerbosity == "")
        sVerbosity = SCHEMA_OUTPUT_VERBOSE;

    if (sSchemaID == "")
        sSchemaID = SCHEMA_DEFAULT_OUTPUT;

    schema_core_CreateTables();

    string s = r"
        CREATE TABLE IF NOT EXISTS schema_output (
            verbosity TEXT NOT NULL,
            schema TEXT NOT NULL,
            output TEXT NOT NULL DEFAULT '{}',
            schema_id TEXT GENERATED ALWAYS AS (json_extract(schema, '$.$id')) STORED,
            PRIMARY KEY (verbosity, schema) ON CONFLICT REPLACE
        );
    ";
    schema_core_ExecuteQuery(s);

    /// @brief If previously built, the output unit at the desired verbosity level will
    ///     exist in the schema_output table.
    s = r"
        SELECT output
        FROM schema_output
        WHERE verbosity = :verbosity
            AND schema_id = :schema_id;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":verbosity", sVerbosity);
    SqlBindString(q, ":schema_id", sSchemaID);

    json joOutputUnit = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    if (JsonGetType(joOutputUnit) == JSON_TYPE_OBJECT)
        return joOutputUnit;

    /// @brief If a stored output unit is not found, attempt to build it by retrieving
    ///     the base output schema from the schema database.  If the output schema
    ///     cannot be found in the schema database, schema_reference_GetSchema() will
    ///     attempt to load the schema from file <sSchemaID>.txt, if it exists.
    json joSchema = schema_reference_GetSchema(sSchemaID);
    if (JsonGetType(joSchema) == JSON_TYPE_NULL)
        return JsonObject();

    s = r"
        WITH RECURSIVE
            input_data AS (
                SELECT 
                    :schema AS schema,
                    :verbosity AS verbosity
                ),
            ref_path AS (
                SELECT json_extract(value, '$.$ref') AS path
                FROM input_data, 
                    json_each(json_extract(schema, '$.anyOf'))
                WHERE json_extract(value, '$.$ref') LIKE '%' || verbosity || '%'
                LIMIT 1
            ),
            ref_to_path AS (
                SELECT 
                    CASE
                        WHEN path LIKE '#/%' THEN '$.' || replace(substr(path, 3), '/', '.')
                        WHEN path = '#' THEN '$'
                        ELSE NULL
                    END AS sqlite_path
                FROM ref_path
            ),
            schema_resolution(sqlite_path, schema_obj, depth) AS (
                SELECT 
                    sqlite_path,
                    json_extract(input_data.schema, sqlite_path) AS schema_obj,
                    1 AS depth
                FROM ref_to_path, input_data
            
                UNION ALL
            
                SELECT
                    CASE
                        WHEN json_extract(schema_obj, '$.$ref') LIKE '#/%' THEN 
                            '$.' || replace(substr(json_extract(schema_obj, '$.$ref'), 3), '/', '.')
                        WHEN json_extract(schema_obj, '$.$ref') = '#' THEN '$'
                        ELSE NULL
                    END AS next_sqlite_path,
                    json_extract(input_data.schema, 
                        CASE
                            WHEN json_extract(schema_obj, '$.$ref') LIKE '#/%' THEN 
                                '$.' || replace(substr(json_extract(schema_obj, '$.$ref'), 3), '/', '.')
                            WHEN json_extract(schema_obj, '$.$ref') = '#' THEN '$'
                            ELSE NULL
                        END
                    ) AS next_schema,
                    depth + 1
                FROM schema_resolution, input_data
                WHERE json_extract(schema_obj, '$.$ref') IS NOT NULL
            ),
            final_schema AS (
                SELECT schema_obj
                FROM schema_resolution
                WHERE json_extract(schema_obj, '$.$ref') IS NULL
                ORDER BY depth DESC
                LIMIT 1
            ),
            required_props AS (
                SELECT value AS prop_name
                FROM final_schema, 
                    json_each(json_extract(schema_obj, '$.required'))
                ),
                prop_types AS (
                SELECT 
                    prop_name,
                    COALESCE(
                        json_extract(json_extract(final_schema.schema_obj, '$.properties.' || prop_name), '$.type'),
                            'object'
                    ) AS prop_type
                FROM required_props, final_schema
            )
        SELECT json_group_object(
            prop_name,
            CASE prop_type
                WHEN 'boolean' THEN true
                WHEN 'string'  THEN json_quote('')
                WHEN 'number'  THEN 0
                WHEN 'integer' THEN 0
                WHEN 'array'   THEN json_array()
                WHEN 'object'  THEN json_object()
                ELSE null
            END
        )
        FROM prop_types;
    ";

    q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":verbosity", sVerbosity);
    SqlBindJson(q, ":schema", joSchema);
    
    if (SqlStep(q))
    {
        json joOutputUnit = SqlGetJson(q, 0);
        if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
            return JsonObject();

        string s = r"
            INSERT INTO schema_output (verbosity, schema, output)
            VALUES (:verbosity, :schema, :output)
            ON CONFLICT(verbosity, schema) DO UPDATE SET
                output = :output;
        ";
        sqlquery q = schema_core_PrepareQuery(s);
        SqlBindString(q, ":verbosity", sVerbosity);
        SqlBindJson(q, ":schema", joSchema);
        SqlBindJson(q, ":output", joOutputUnit);

        SqlStep(q);
        return joOutputUnit;
    }

    return JsonObject();
}

/// @private Set the `keywordLocation` value into joOutputUnit by constructing the current schema
///     path from the schema path scope.
json schema_output_SetKeywordLocation(json joOutputUnit)
{
    return JsonObjectSet(joOutputUnit, "keywordLocation", JsonString(schema_scope_ConstructSchemaPath()));
}

/// @private Set the `instanceLocation` value into joOutputUnit by constructing the current instance
///     path from the instance path scope.
json schema_output_SetInstanceLocation(json joOutputUnit)
{
    return JsonObjectSet(joOutputUnit, "instanceLocation", JsonString(schema_scope_ConstructInstancePath()));
}

/// @private Set the `absoluteKeywordLocation` value into joOutputUnit by constructing the current
///     absolute schema path from the absolute schema path scope.
json schema_output_SetAbsoluteKeywordLocation(json joOutputUnit)
{
    /// @todo
    ///      [ ] Need the functionality to build the absolute keyword pointer
    return JsonObjectSet(joOutputUnit, "absoluteKeywordLocation", JsonString("@todo"));
}

/// @private Build an output unit skeleton.  keywordLocation and instanceLocation are populated here
///     for use by parent nodes.  Child nodes will have these values overwritten as annotations and
///     errors are added.
/// @note keyword valid is set to TRUE here even though the query in schema_output_GetMinimalObject()
///     specifies a value of `true` as the value is sometimes translated to integer 1 and no longer
///     recognized as boolean for comparison purposes.
json schema_output_GetOutputUnit(string sSource = "")
{
    /// @todo
    ///     [ ] or make it a user configuration (source)
    ///     [ ] change default boolean to null?

    json joOutputUnit = schema_output_GetMinimalObject();
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);
    joOutputUnit = schema_output_SetValid(joOutputUnit, TRUE);

    if (SOURCE)
    {
        if (sSource == "") joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString("default"));
        else joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(" :: " + sSource + " :: "));
    }

    /// @todo temp for testing
    joOutputUnit = JsonObjectSet(joOutputUnit, "uuid", JsonString(GetRandomUUID()));

    return joOutputUnit;
}

/// @private Insert an error object into the parent node's errors array.
json schema_output_InsertError(json joOutputUnit, json joError, string sSource = "")
{
    if (JsonGetType(joError) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    if (JsonGetType(jaErrors) != JSON_TYPE_ARRAY)
        jaErrors = JsonArray();

    jaErrors = JsonArrayInsert(jaErrors, joError);
    joOutputUnit = JsonObjectSet(joOutputUnit, "errors", jaErrors);
    joOutputUnit = schema_output_SetValid(joOutputUnit, FALSE);

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joOutputUnit); 
    return joOutputUnit;
}

/// @private Insert an annotation object into the parent node's annotations array.
json schema_output_InsertAnnotation(json joOutputUnit, json joAnnotation, string sSource = "")
{
    if (JsonGetType(joAnnotation) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaAnnotations = JsonObjectGet(joOutputUnit, "annotations");
    if (JsonGetType(jaAnnotations) != JSON_TYPE_ARRAY)
        jaAnnotations = JsonArray();

    jaAnnotations = JsonArrayInsert(jaAnnotations, joAnnotation);
    joOutputUnit = JsonObjectSet(joOutputUnit, "annotations", jaAnnotations);

    json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    int bValid = JsonGetType(jaErrors) == JSON_TYPE_ARRAY && JsonGetLength(jaErrors) > 0;
        
    joOutputUnit = schema_output_SetValid(joOutputUnit, !bValid);
    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joOutputUnit); 

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

    return joOutputUnit;
}

/// @todo
///     [ ] how do we handle failed keyword validations that may not fail the entire schema?

/// @private Insert an error string in an output unit.
json schema_output_SetError(json joOutputUnit, string sError, string sSource = "")
{
    joOutputUnit = JsonObjectSet(joOutputUnit, "error", JsonString(sError));
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

    return schema_output_SetValid(joOutputUnit, FALSE);
}

/// @private Insert an annotation key:value pair into an output unit.
json schema_output_SetAnnotation(json joOutputUnit, string sKey, json jValue, string sSource = "")
{
    joOutputUnit = JsonObjectSet(joOutputUnit, sKey, jValue);
    joOutputUnit = schema_output_SetKeywordLocation(joOutputUnit);
    joOutputUnit = schema_output_SetInstanceLocation(joOutputUnit);

    if (SOURCE && sSource != "")
        joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));

    //json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    //int bValid = JsonGetType(jaErrors) == JSON_TYPE_ARRAY && JsonGetLength(jaErrors) > 0;

    return joOutputUnit;

    //return schema_output_SetValid(joOutputUnit, !bValid);
}

/// @private Return a an array of all keys previously evaluated by sAnnotationKey.  This
///     query will pull all instances of `evaluated*` from validation results contained
///     int joOutputUnit.  This methodology is required to property validate instances
///     against `unevaluatedProperties` and `unevaluatedItems`.
/// @param joOutputUnit Output unit.
/// @param sAnnotationKey Key to serach for in joOutputUnit.
/// @returns Sorted, unique array of all evaluated keys.
json schema_output_GetEvaluatedKeys(json joOutputUnit, string sAnnotationKey)
{
    string s = r"
        WITH source_list AS (
            SELECT value 
            FROM json_each(
                CASE WHEN json_type(:output_unit) = 'array' THEN :output_unit
                ELSE json_extract(:output_unit, '$.annotations')
                END
            )
        )
        SELECT json_group_array(DISTINCT item.value)
        FROM (
            SELECT kv.value AS val
            FROM source_list AS direct_anno
            JOIN json_each(direct_anno.value) AS kv
            WHERE kv.key = :annotation_key 
               OR (:annotation_key = 'evaluatedProperties' AND kv.key IN ('properties', 'patternProperties', 'additionalProperties', 'unevaluatedProperties'))
               OR (:annotation_key = 'evaluatedItems' AND kv.key IN ('prefixItems', 'items', 'contains', 'unevaluatedItems'))
            
            UNION ALL

            SELECT child_kv.value AS val
            FROM source_list AS direct_anno
            JOIN json_each(json_extract(direct_anno.value, '$.annotations')) AS child_anno
            JOIN json_each(child_anno.value) AS child_kv
            WHERE child_kv.key = :annotation_key
        ) AS combined
        JOIN json_each(combined.val) AS item;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":output_unit", joOutputUnit);
    SqlBindString(q, ":annotation_key", sAnnotationKey);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonArray();
}

/// @private Convenience function to retrieve all evaluated properties from jOutputUnit.
json schema_output_GetEvaluatedProperties(json joOutputUnit)
{
    return schema_output_GetEvaluatedKeys(joOutputUnit, "evaluatedProperties");
}

/// @private Convenience function to retrieve all evaluated items from joOutputUnit.
json schema_output_GetEvaluatedItems(json joOutputUnit)
{
    return schema_output_GetEvaluatedKeys(joOutputUnit, "evaluatedItems");
}

/// @todo
///     See where *Inplace functions can be used to make json building faster, in the few
///         places where json objects are built from scratch or modified directly.  The
///         scope management functions will probably benefit the most from this methodology.
///         *Inplace functions are twice as fast as building a new object and they modify
///         the saved value direction, so can even avoid the SetLocalJson calls (?).

/// @private Aggregate evaluated keys from adjacent and child nodes, compare to
///     the entire set of instance keys and return the unevaluated keys as an array.
/// @param joOutputUnit The output unit.
/// @param jaInstanceKeys Array of all available instance keys.
/// @param sAnnotationKey Annotation key to find in joOutputUnit.
json schema_output_GetUnevaluatedKeys(json joOutputUnit, json jaInstanceKeys, string sAnnotationKey)
{
//    string s = r"
//        SELECT json_group_array(avail.value)
//        FROM json_each(:instance_keys) AS avail
//        WHERE avail.value NOT IN (
//            SELECT value
//            FROM json_each(:evaluated_keys)
//        )
//        ORDER BY avail.value;
//    ";
//    sqlquery q = schema_core_PrepareQuery(s);
//    SqlBindJson(q, ":instance_keys", jaInstanceKeys);
//    SqlBindJson(q, ":evaluated_keys", schema_output_GetEvaluatedKeys(joOutputUnit, sAnnotationKey));
//
//    return SqlStep(q) ? SqlGetJson(q, 0) : JsonArray();

    /// @todo This is a change to see if we can end around the issue with encoding and comparing
    ///     non-ascii characters, which the sql doesn't like since they have to be decoded before
    ///     binding, which causes all kinds of issues.
    json jaEvaluatedKeys = schema_output_GetEvaluatedKeys(joOutputUnit, sAnnotationKey);
    json jaUnevaluatedKeys = JsonArray();
    
    int i; for (; i < JsonGetLength(jaInstanceKeys); i++)
    {
        json jKey = JsonArrayGet(jaInstanceKeys, i);
        if (JsonFind(jaEvaluatedKeys, jKey) == JsonNull())
            JsonArrayInsertInplace(jaUnevaluatedKeys, jKey);
    }

    return jaUnevaluatedKeys;
}

/// @private Convenience function to retrieve all unevaluated properties from joOutputUnit.
json schema_output_GetUnevaluatedProperties(json joOutputUnit, json jInstanceData)
{
    if (JsonGetType(jInstanceData) == JSON_TYPE_OBJECT)
        jInstanceData = JsonObjectKeys(jInstanceData);

    return schema_output_GetUnevaluatedKeys(joOutputUnit, jInstanceData, "evaluatedProperties");
}

/// @private Convenience function to retrieve all unevaluated items from joOutputUnit.
json schema_output_GetUnevaluatedItems(json joOutputUnit, json jInstanceData)
{
    json jaInstanceIndexes = JsonArray();
    int i; for (; i < JsonGetLength(jInstanceData); i++)
        JsonArrayInsertInplace(jaInstanceIndexes, JsonInt(i));

    return schema_output_GetUnevaluatedKeys(joOutputUnit, jaInstanceIndexes, "evaluatedItems");
}

/// @private Insert an annoation or error output unit into the appropriate array in joOutputUnit.
json schema_output_InsertResult(json joOutputUnit, json joResult, string sSource)
{
    if (schema_output_GetValid(joResult))
        joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joResult, sSource);
    else
        joOutputUnit = schema_output_InsertError(joOutputUnit, joResult, sSource);

    return joOutputUnit;
}

/// @private Reduce a verbose output unit to a flag.
json schema_output_Flag(json joOutputUnit)
{
    if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
        return JSON_NULL;

    /// @todo
    ///     [ ] This JsonFind won't work, need the key array
    if (JsonFind(joOutputUnit, JsonString("valid")) == JsonNull())
        return JSON_NULL;

    return JsonObjectSet(JsonObject(), "valid", JsonObjectGet(joOutputUnit, "valid"));
}

/// @private Reduce a verbose output unit to a list of errors without nested context.
json schema_output_Basic(json joOutputUnit)
{
    if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
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

    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":output", joOutputUnit);

    return SqlStep(q) ? SqlGetJson(q, 0) : JSON_NULL;
}

/// @todo this output still needs work to remove any valid results entries as well as
///       collapsing/removing as required by json-schema.org
json schema_output_Detailed(json joOutputUnit)
{
    if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
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

    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":output", joOutputUnit);

    return SqlStep(q) ? SqlGetJson(q, 0) : JSON_NULL;
}

/// -----------------------------------------------------------------------------------------------
///                                     REFERENCE MANAGEMENT
/// -----------------------------------------------------------------------------------------------
/// @brief Schema reference management functions.  These functions provide a method for identifying,
///     resolving and utilizing $anchor, $dynamicAnchor, $ref and $dynamicRef keywords.

/// @todo
///     [ ] Build documentation!



/// @private Normalize a path that contains empty segments, or hierarchical segments such as
///     "." and "..".
/// @param sPath The path to normalize.
/// @returns A normalized path string with empty segments and hierarchical segments resolved.
string schema_reference_NormalizePath(string sPath)
{
    json jaParts = schema_scope_Deconstruct(sPath);
    json jaStack = JsonArray();

    int i, n = JsonGetLength(jaParts);
    for (i = 0; i < n; i++)
    {
        string s = JsonGetString(JsonArrayGet(jaParts, i));
        s = schema_reference_UnescapePointer(s);
        
        if (s == "" || s == ".")
        {
            continue;
        }
        if (s == "..")
        {
            if (JsonGetLength(jaStack) > 0)
                jaStack = JsonArrayGetRange(jaStack, 0, -2);
            continue;
        }

        jaStack = JsonArrayInsert(jaStack, JsonString(s));
    }

    return schema_scope_Construct(jaStack);
}

json schema_reference_ResolveAnchor(json joSchema, string sAnchor)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sAnchor", JsonString(sAnchor));

    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT || sAnchor == "")
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return JsonNull();
    }

    string s = r"
        WITH 
            tree AS (SELECT * FROM json_tree(:schema)),
            root AS (SELECT id FROM tree WHERE parent IS NULL),
            resources AS (
                SELECT parent AS id 
                FROM tree 
                WHERE key IN ('$id', 'id') AND type = 'text'
            ),
            candidates AS (
                SELECT parent AS id
                FROM tree
                WHERE key = '$anchor' AND atom = :anchor
            ),
            ancestors(candidate_id, current_id) AS (
                SELECT id, id FROM candidates
                UNION ALL
                SELECT a.candidate_id, t.parent
                FROM ancestors a
                JOIN tree t ON t.id = a.current_id
                WHERE t.parent IS NOT NULL
            )
        SELECT t.value
        FROM candidates c
        JOIN tree t ON t.id = c.id
        WHERE NOT EXISTS (
            SELECT 1
            FROM ancestors a
            JOIN resources r ON r.id = a.current_id
            WHERE a.candidate_id = c.id
            AND a.current_id != (SELECT id FROM root)
        )
        LIMIT 1;
    ";

    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindString(q, ":anchor", sAnchor);

    json jResult = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    
    schema_debug_ExitFunction(__FUNCTION__);
    return jResult;
}

json schema_reference_ResolvePointer(json joSchema, string sPointer)
{
    if (sPointer == "")
        return joSchema;

    json jaParts = schema_scope_Deconstruct(sPointer);
    json jCurrent = joSchema;
    int i, n = JsonGetLength(jaParts);

    for (i = 0; i < n; i++)
    {
        string sPart = JsonGetString(JsonArrayGet(jaParts, i));
        sPart = schema_reference_UnescapePointer(sPart);

        int nType = JsonGetType(jCurrent);
        if (nType == JSON_TYPE_OBJECT)
        {
            if (!schema_util_HasKey(jCurrent, sPart))
                return JsonNull();
            jCurrent = schema_util_JsonObjectGet(jCurrent, sPart);
        }
        else if (nType == JSON_TYPE_ARRAY)
        {
            int nIndex = StringToInt(sPart);
            // Check if sPart is a valid integer string and within bounds
            if (IntToString(nIndex) != sPart || nIndex < 0 || nIndex >= JsonGetLength(jCurrent))
                return JsonNull();
            jCurrent = JsonArrayGet(jCurrent, nIndex);
        }
        else
        {
            return JsonNull();
        }
    }

    return jCurrent;
}

/// @private Remove a schema from the database by its ID.
/// @param sID The ID of the schema to remove.
/// @note If a schema file exists, this function does not delete that file.
void schema_reference_DeleteSchema(string sID)
{
    if (sID == "")
        return;

    schema_core_CreateTables();

    string s = r"
        DELETE FROM schema_schema
        WHERE schema_id = :schema_id;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":schema_id", sID);

    SqlStep(q);
}

/// @private Add a validated schema to the database.
/// @param joSchema The json object representing the schema to save.
/// @warning This function should only be called after the schema has been validated.
///     Invalid schema objects may cause undefined or unexpected behavior.
void schema_reference_SaveSchema(json joSchema)
{
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
        return;

    schema_core_CreateTables();

    string sID = JsonGetString(JsonObjectGet(joSchema, "$id"));
    if (sID == "")
        return;

    string s = r"
        INSERT INTO schema_schema (schema)
        VALUES (:schema);
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":schema", joSchema);

    SqlStep(q);
}

/// @todo
///     [ ] Track where these JsonNull() get returns and figure out what to do with them.
///     [ ] Add an annotation here if $schema = "" or could not be found in db.
///     [ ] Need better error handling/messaging here.  Structured logging?
///     [ ] Ensure $dynamicReference acts like $ref if the $dynamicAnchor can't be located.

json schema_reference_GetSchema(string sSchemaID)
{
    if (sSchemaID == "")
        return JsonNull();

    // Check the current document's ID map first
    json joIDMap = GetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP");
    if (JsonGetType(joIDMap) == JSON_TYPE_OBJECT)
    {
        json joSchema = JsonObjectGet(joIDMap, sSchemaID);
        if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
            return joSchema;
    }

    schema_core_CreateTables();

    string s = r"
        SELECT schema 
        FROM schema_schema
        WHERE schema_id = :id
            OR schema_id = :id || '#';
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":id", sSchemaID);

    json joSchema = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
        return joSchema;

    /// @note Attempt to retrieve the schema from the admin table.
    q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":id", sSchemaID);

    joSchema = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
        return joSchema;

    /// @note Attempt to retrieve the schema from a ResMan file.
    if (GetStringLength(sSchemaID) <= 16 && ResManGetAliasFor(sSchemaID, RESTYPE_TXT) != "")
    {
        joSchema = JsonParse(ResManGetFileContents(sSchemaID, RESTYPE_TXT));
        if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
        {
            /// @note File-sourced schema are not trusted, so validation must
            ///     be performed before saving the schema to the database.
            string sSchema = JsonGetString(JsonObjectGet(joSchema, "$schema"));
            if (sSchema == "")
                sSchema = SCHEMA_DEFAULT_DRAFT;

            json joMeta = schema_reference_GetSchema(sSchema);
            if (JsonGetType(joMeta) == JSON_TYPE_NULL && sSchema != SCHEMA_DEFAULT_DRAFT)
                joMeta = schema_reference_GetSchema(SCHEMA_DEFAULT_DRAFT);

            if (JsonGetType(joMeta) == JSON_TYPE_NULL)
                return JsonNull();
            else
            {
                schema_scope_IncrementDepth();
                json joResult = schema_core_Validate(joSchema, joMeta);
                schema_scope_DecrementDepth();

                if (schema_output_GetValid(joResult))
                {
                    schema_reference_SaveSchema(joSchema);
                    return joSchema;
                }
                else
                    return JsonNull();
            }
        }
    }

    return JsonNull();
}

/// @todo
///     [ ] Is this where we need ~0 and ~1 resolution?
///     [ ] Support id's in refs? so that if a ref schema is found, and it has an id
///         it should be validated as a a new depth so all the new data can be used for it?
///         how does that interplay with our context?
///     [ ] need to support ~0 and ~1 somewheres!

/// @private Resolve a fragment reference within a $ref.
/// @param joSchema The base schema to resolve the fragment against.
/// @param sFragment The fragment string to resolve.
/// @returns The resolved fragment, or JsonNull() if the fragment
///     could not be resolved.
json schema_reference_ResolveFragment(json joSchema, string sFragment)
{
    sFragment = schema_reference_DecodeURI(sFragment);

    if (GetStringLeft(sFragment, 1) == "/")
        return schema_reference_ResolvePointer(joSchema, sFragment);
    else
    {
        json joAnchor = schema_reference_ResolveAnchor(joSchema, sFragment);
        if (JsonGetType(joAnchor) == JSON_TYPE_NULL)
            joAnchor = schema_util_JsonObjectGet(joSchema, sFragment);

        return joAnchor;
    }
}

string schema_reference_MergePath(json jaMatchBase, string sPathRef)
{
    if (JsonGetString(JsonArrayGet(jaMatchBase, 3)) != "" &&
        JsonGetString(JsonArrayGet(jaMatchBase, 5)) == "")
        return "/" + sPathRef;
    else
    {
        string sPathBase = JsonGetString(JsonArrayGet(jaMatchBase, 5));
        json jaMatch = RegExpMatch("^(.*\\/)", sPathBase);
        if (JsonGetType(jaMatch) != JSON_TYPE_NULL && jaMatch != JsonArray())
            return JsonGetString(JsonArrayGet(jaMatch, 1)) + sPathRef;
        else
            return sPathRef;
    }
}

/// @private Determine is members of jaMatch meet desired existence
///     criteria defined in jaCriteria.
/// @param jaMatch Uri-reference match results.
/// @param jaCriteria Existence criteria array.
/// @returns TRUE for a successful match, FALSE otherwise.
/// @note jaCriteria must be an 10-element array containing the integers
///     -1, 0 or 1.  No other values are valid.  This function will compare
///     each member in jaMatch to it's matching-index member in jaCriteria.
///         -1: Value of matching index is ignored
///          0: Value of matching index must be a zero-length string
///          1: Value of matching index must be a greater-than-zero-length string
int schema_reference_CheckMatch(json jaMatch, json jaCriteria)
{
    string s = r"
        WITH
            numbers(n) AS (
                SELECT 0
                UNION ALL
                SELECT n + 1 FROM numbers WHERE n + 1 < json_array_length(:criteria)
            ),
            pairs AS (
                SELECT n,
                    json_extract(:match, '$[' || n || ']') AS t,
                    json_extract(:criteria, '$[' || n || ']') AS c
                FROM numbers
                WHERE json_extract(:criteria, '$[' || n || ']') != -1
            )
        SELECT
            CASE
                WHEN SUM(
                    CASE
                        WHEN c = 1 AND (t IS NULL OR t = '') THEN 1
                        WHEN c = 0 AND (t IS NOT NULL AND t != '') THEN 1
                        ELSE 0
                    END
                ) = 0
                THEN 1
                ELSE 0
            END
        FROM pairs;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":match", jaMatch);
    SqlBindJson(q, ":criteria", jaCriteria);

    return SqlStep(q) ? SqlGetInt(q, 0) : FALSE;
}

/// @private Resolve a $ref.  This function follows closesly the uri resolution
///     algorithm defined in RFC 3986, Section 5.2.  It handles both absolute and
///     relative references, as well as fragment-only references.
/// @param joSchema The base schema to resolve the reference against.
/// @param jsRef The $ref json object to resolve.
/// @returns The resolved schema, or the base schema if no resolution is possible.
json schema_reference_ResolveRef(json joSchema, json jsRef)
{
    json joBaseSchema = schema_scope_GetBaseSchema();
    string sRef = JsonGetString(jsRef);
    
    string sBaseURI = JsonGetString(JsonObjectGet(joBaseSchema, "$id"));
    if (sBaseURI == "") sBaseURI = JsonGetString(JsonObjectGet(joBaseSchema, "id"));
    
    string sFullURI = schema_reference_ResolveURI(sBaseURI, sRef);
    
    int nFragmentPos = FindSubString(sFullURI, "#");
    string sSchemaID = sFullURI;
    string sFragment = "";
    
    if (nFragmentPos != -1)
    {
        sSchemaID = GetStringLeft(sFullURI, nFragmentPos);
        sFragment = GetStringRight(sFullURI, GetStringLength(sFullURI) - nFragmentPos - 1);
    }
    
    json joTargetSchema;
    if (sSchemaID == "" || sSchemaID == sBaseURI)
        joTargetSchema = joBaseSchema;
    else
        joTargetSchema = schema_reference_GetSchema(sSchemaID);
    
    if (JsonGetType(joTargetSchema) == JSON_TYPE_NULL)
        return JsonNull();
        
    if (sFragment == "")
        return joTargetSchema;
        
    return schema_reference_ResolveFragment(joTargetSchema, sFragment);
}

/// @todo
///     [ ] See who is receiving the JsonNull() and handle it.

/// @private Resolve a dynamic anchor subschema from the current dynamic scope.
/// @param jsRef The dynamic anchor to resolve.
/// @returns The resolved dynamic anchor schema as a json object, or an empty
///     json object if not found.
json schema_reference_ResolveDynamicRef(json joSchema, json jsRef, int bRevertToRef = FALSE)
{
    json jaDynamic = schema_scope_GetDynamic();
    if (JsonGetType(jaDynamic) != JSON_TYPE_ARRAY || JsonGetLength(jaDynamic) == 0)
        return JsonNull();

    json jaSchema = JsonArrayGet(jaDynamic, schema_scope_GetDepth());
    if (JsonGetType(jaSchema) != JSON_TYPE_OBJECT || JsonGetLength(jaSchema) == 0)
        return JsonNull();

    int i; for (i = JsonGetLength(jaSchema); i > 0; i--)
    {
        json joScope = JsonArrayGet(jaSchema, i);
        json jsAnchor = JsonObjectGet(joScope, "$dynamicAnchor");
        if (JsonGetType(jsAnchor) == JSON_TYPE_STRING && jsAnchor == jsRef)
            return joScope;
    }

    return bRevertToRef ? schema_reference_ResolveRef(joSchema, jsRef) : JsonNull();
}

/// @todo
///     [ ] does this work?  I forgot how the scopes work, it's been soooo long .....
json schema_reference_ResolveRecursiveRef(json joSchema)
{
    json jaDynamic = schema_scope_GetDynamic();
    // if (JsonGetType(jaDynamic) != JSON_TYPE_ARRAY || JsonGetLength(jaDynamic) == 0)
    //    return JsonNull();

    /*
    json jaSchema = JsonArrayGet(jaDynamic, schema_scope_GetDepth());
    if (JsonGetType(jaSchema) != JSON_TYPE_ARRAY || JsonGetLength(jaSchema) == 0)
        return JsonNull();

    int i; for (i = 0; i < JsonGetLength(jaSchema); i++)
    {
        json joScope = JsonArrayGet(jaSchema, i);
        json jsAnchor = JsonObjectGet(joScope, "$recursiveAnchor");
        if (JsonGetType(jsAnchor) == JSON_TYPE_BOOL && jsAnchor == JSON_TRUE)
            return joScope;
    }
    */

    // jaDynamic is the stack of scopes for the current depth.
    // We iterate through the stack to find the recursive anchor.
    /*
    int i; for (i = 0; i < JsonGetLength(jaDynamic); i++)
    {
        json joScope = JsonArrayGet(jaDynamic, i);
        json jsAnchor = JsonObjectGet(joScope, "$recursiveAnchor");
        if (JsonGetType(jsAnchor) == JSON_TYPE_BOOL && jsAnchor == JSON_TRUE)
            return joScope;
    }
    */

    json jRef = JsonObjectGet(joSchema, "$recursiveRef");
    json joTarget = schema_reference_ResolveRef(joSchema, jRef);

    if (JsonGetType(joTarget) == JSON_TYPE_NULL)
        return JsonNull();

    json jsAnchor = JsonObjectGet(joTarget, "$recursiveAnchor");
    if (JsonGetType(jsAnchor) != JSON_TYPE_BOOL || jsAnchor != JSON_TRUE)
        return joTarget;

    if (JsonGetType(jaDynamic) != JSON_TYPE_ARRAY || JsonGetLength(jaDynamic) == 0)
        return joTarget;

    int i; for (i = 0; i < JsonGetLength(jaDynamic); i++)
    {
        json joScope = JsonArrayGet(jaDynamic, i);
        json jsScopeAnchor = JsonObjectGet(joScope, "$recursiveAnchor");
        if (JsonGetType(jsScopeAnchor) == JSON_TYPE_BOOL && jsScopeAnchor == JSON_TRUE)
            return joScope;
    }

    return joTarget;
}

/// @private Load the keyword type map for the specified schema ID from the database.
json schema_keyword_LoadTypeMap(string sSchemaID)
{
    string s = r"
        SELECT k.keyword
        FROM schema_keyword k
        JOIN schema_schema s ON k.schema_id = s.id
        WHERE s.schema_id = :id;
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindString(q, ":id", sSchemaID);

    json joMap = JsonObject();
    while (SqlStep(q))
    {
        string sKeyword = SqlGetString(q, 0);
        joMap = JsonObjectSet(joMap, sKeyword, JsonBool(TRUE));
    }

    if (JsonGetLength(joMap) == 0)
        return JsonNull();

    return joMap;
}

/// -----------------------------------------------------------------------------------------------
///                                     KEYWORD VALIDATION
/// -----------------------------------------------------------------------------------------------

/// @todo
///     [ ] Need handling methodology for the following keywords to support versioning:
///         [ ] $recursiveRef, $recursiveAnchor: only supported in draft-2019-09; deprecated in draft-2020-12
///         [ ] 'id' (superseded by '$id' in draft-6)
///         [ ] definitions (deprecated in draft-2020-12, replaced by '$defs')
///     [ ] How do we handle an nDraft = 0 (i.e. the current schema is a string, not a json-schema.org draft)?
///         if nDraft = 0, then it's not a draft schema, so we shouldn't be here anyway?

///     [ ] Need an "environment prep" function that can be called by the entrant functions that will
///         [ ] set the current metaschema draft version
///         [ ] Schedule build variables for destruction
///         [ ] hold full current/starting schema for $ref purposes

/// @brief Validates the global "type" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "type".
/// @returns An output object containing the validation result.
json schema_validate_Type(json jInstance, json jSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "jInstance", jInstance);
    schema_debug_Argument(__FUNCTION__, "jSchema", jSchema);

    json joOutputUnit = schema_output_GetOutputUnit();

    string sSource = __FUNCTION__;
    string sKeyword = "type";

    int nTypeType = JsonGetType(jSchema);
    if (nTypeType == JSON_TYPE_STRING)
    {
        int nInstanceType = JsonGetType(jInstance);

        if (JsonGetString(jSchema) == "number")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
            {
                schema_debug_ExitFunction(__FUNCTION__);
                return schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
            }
        }
        else if (JsonGetString(jSchema) == "integer")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
            {
                /// @note We're using a query here in case we run into numbers larger than
                ///     the signed 32-bit maximum.
                string s = r"
                    SELECT (CAST(val AS INTEGER) == val)
                    FROM (SELECT json_extract(:instance, '$') AS val);
                ";
                sqlquery q = SqlPrepareQueryObject(GetModule(), s);
                SqlBindJson(q, ":instance", jInstance);

                if (SqlStep(q) ? SqlGetInt(q, 0) : FALSE)
                {
                    schema_debug_ExitFunction(__FUNCTION__);
                    return schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
                }
            }
        }
        else
        {
            json jaTypes = JsonParse(r"[
                ""null"",
                ""object"",
                ""array"",
                ""string"",
                ""integer"",
                ""float"",
                ""boolean""
            ]");

            json jiFind = JsonFind(jaTypes, jSchema);
            if (JsonGetType(jiFind) != JSON_TYPE_NULL && JsonGetInt(jiFind) == nInstanceType)
            {
                schema_debug_ExitFunction(__FUNCTION__);
                return schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
            }
        }
    }
    else if (nTypeType == JSON_TYPE_ARRAY)
    {
        int i; for (; i < JsonGetLength(jSchema); i++)
        {
            json joValidate = schema_validate_Type(jInstance, JsonArrayGet(jSchema, i));
            if (schema_output_GetValid(joValidate))
                joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joValidate, sSource + " (array)");
        }
    }

    json jaAnnotations = JsonObjectGet(joOutputUnit, "annotations");

    schema_debug_ExitFunction(__FUNCTION__);

    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL || JsonGetLength(jaAnnotations) == 0)
        return schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    else if (nTypeType == JSON_TYPE_ARRAY && JsonGetLength(jaAnnotations) > 0)
        return schema_output_SetAnnotation(schema_output_GetOutputUnit(), sKeyword, jSchema, sSource);
    
    return joOutputUnit;
}

/// @brief Validates the global "enum" and "const" keywords.
/// @param jInstance The instance to validate.
/// @param jSchema The array of valid elements for enum/const. Assumed to be validated against the metaschema.
/// @returns An output object containing the validation result.
/// @note Due to NWN's nlohmann::json implementation, JsonFind() conducts a
///     deep comparison of the instance and enum/const values; separate handling
///     for the various json types is not required.
json schema_validate_Enum(json jInstance, json jSchema, string sKeyword)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "jInstance", jInstance);
    schema_debug_Argument(__FUNCTION__, "jSchema", jSchema);

    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    if (sKeyword == "const")
        jSchema = JsonArrayInsert(JsonArray(), jSchema);

    schema_debug_ExitFunction(__FUNCTION__);

    if (JsonGetType(JsonFind(jSchema, jInstance)) != JSON_TYPE_NULL)
        return joOutputUnit;

    // Fallback for strings with encoding issues
    if (JsonGetType(jInstance) == JSON_TYPE_STRING)
    {
        string sQuery = "SELECT 1 FROM json_each(:schema) WHERE " +
            "CAST(CAST(value AS BLOB) AS TEXT) = " +
            "CAST(CAST(json_extract(json(:instance), '$') AS BLOB) AS TEXT)";

        sqlquery q = schema_core_PrepareQuery(sQuery);
        SqlBindJson(q, ":schema", jSchema);
        SqlBindJson(q, ":instance", jInstance);

        if (SqlStep(q))
            return joOutputUnit;
    }

    return schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @todo
///     integrate these more cleanly for non-ascii characters.

/// @brief Checks if a string matches a regex pattern using SQLite's REGEXP operator.
/// @param sPattern The regex pattern.
/// @param sString The string to check.
/// @returns TRUE if the string matches the pattern, FALSE otherwise.
int schema_util_RegExpMatch(string sPattern, string sString)
{
    string s = r"
        SELECT 1
        WHERE
            CAST(CAST(json_extract(json(:string), '$') AS BLOB) AS TEXT)
            REGEXP
            CAST(CAST(json_extract(json(:pattern), '$') AS BLOB) AS TEXT);
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":string", JsonString(sString));
    SqlBindJson(q, ":pattern", JsonString(sPattern));
    return SqlStep(q);
}

/// @brief Retrieves a value from a JSON object by key, with a fallback to SQLite
///     if the native JsonObjectGet fails (e.g. due to encoding issues with keys).
/// @param jObject The JSON object.
/// @param sKey The key to retrieve.
/// @returns The value associated with the key, or JsonNull() if not found.
json schema_util_JsonObjectGet(json jObject, string sKey)
{
    json jValue = JsonObjectGet(jObject, sKey);
    if (JsonGetType(jValue) != JSON_TYPE_NULL) return jValue;

    // Use SQLite fallback to handle potential encoding mismatches in keys
    // We must use json_quote for text values because json_each returns unquoted text,
    // which SqlGetJson cannot parse as a JSON string.
    string s = r"
        SELECT CASE 
            WHEN type = 'text'
                THEN json_quote(value)
                ELSE value
            END
        FROM json_each(:obj)
        WHERE
            CAST(CAST(key AS BLOB) AS TEXT) = CAST(CAST(json_extract(json(:key), '$') AS BLOB) AS TEXT);
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":obj", jObject);
    SqlBindJson(q, ":key", JsonString(sKey));
    
    return SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
}

/// @brief Checks if a key exists in a JSON object, with a fallback to SQLite
///     to handle potential encoding mismatches.
/// @param jObject The JSON object.
/// @param sKey The key to check.
/// @returns TRUE if the key exists, FALSE otherwise.
int schema_util_HasKey(json jObject, string sKey)
{
    if (JsonGetType(JsonObjectGet(jObject, sKey)) != JSON_TYPE_NULL) return TRUE;

    // If the value is actually null, JsonObjectGet returns JSON_TYPE_NULL, which is ambiguous.
    // But if we are here, either the key is missing OR the value is null.
    // So we need to check if the key actually exists.
    // Also handles the encoding fallback.

    string s = r"
        SELECT 1
        FROM json_each(:obj)
        WHERE 
            CAST(CAST(key AS BLOB) AS TEXT) = CAST(CAST(json_extract(json(:key), '$') AS BLOB) AS TEXT);
    ";
    sqlquery q = schema_core_PrepareQuery(s);
    SqlBindJson(q, ":obj", jObject);
    SqlBindJson(q, ":key", JsonString(sKey));
    
    return SqlStep(q);
}

/// @brief Validates the string "pattern" keyword.
/// @param jsInstance The instance to validate.
/// @param jSchema The schema value for "pattern".
/// @returns An output object containing the validation result.
json schema_validate_Pattern(json jsInstance, json jSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json joOutputUnit = schema_output_GetOutputUnit();
    
    string sSource = __FUNCTION__;
    string sKeyword = "pattern";

    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return joOutputUnit;
    }

    schema_debug_ExitFunction(__FUNCTION__);
    if (schema_util_RegExpMatch(JsonGetString(jSchema), JsonGetString(jsInstance)))
        return joOutputUnit;
    else
        return schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @todo
///     [ ] This whole function

/// @brief Validates the string "format" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "format".
/// @returns An output object containing the validation result.
json schema_validate_Format(json jInstance, json jSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json joOutputUnit = schema_output_GetOutputUnit();

    if (JsonGetType(jInstance) != JSON_TYPE_STRING)
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return joOutputUnit;
    }

    string sInstance = JsonGetString(jInstance);
    string sFormat = JsonGetString(jSchema);
    int bValid = FALSE;

    if (sFormat == "email")    
    {
        bValid = schema_util_RegExpMatch("^[a-zA-Z0-9!#$%&'*+\\-/=?^_`{|}~]+(?:\\.[a-zA-Z0-9!#$%&'*+\\-/=?^_`{|}~]+)*@(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$", sInstance);
    }
    else if (sFormat == "hostname")
    {
        // Use a recursive CTE to split the hostname by dots, avoiding JSON injection risks
        string s = r"
            WITH RECURSIVE split(word, str) AS (
                SELECT '', :data || '.'
                UNION ALL
                SELECT substr(str, 0, instr(str, '.')), substr(str, instr(str, '.') + 1)
                FROM split
                WHERE str != ''
            ),
            labels AS (
                SELECT word AS label FROM split WHERE word != ''
            ),
            validation_results AS (
                SELECT 
                CASE 
                    -- 1. Label length 1-63
                    WHEN length(label) < 1 OR length(label) > 63 THEN 0
                    -- 2. No hyphens at start or end
                    WHEN label LIKE '-%' OR label LIKE '%-' THEN 0
                    -- 3. Only alphanumeric and hyphens
                    WHEN label NOT REGEXP '^[a-zA-Z0-9-]+$' THEN 0
                    -- 4. Position 3-4 check (RFC 5890)
                    WHEN substr(label, 3, 2) = '--' AND substr(label, 1, 4) != 'xn--' THEN 0
                    -- 5. Punycode prefix must be lowercase
                    WHEN substr(label, 1, 4) IN ('XN--', 'xN--', 'Xn--') THEN 0
                    ELSE 1 
                END AS is_label_valid
                FROM labels
            )
            -- If total length > 253 or any label is invalid, return 0
            SELECT 
                CASE 
                    WHEN length(:data) > 253 THEN 0 
                    ELSE MIN(is_label_valid) 
                END
            FROM validation_results;
        ";
        sqlquery q = SqlPrepareQueryObject(GetModule(), s);
        SqlBindString(q, ":data", sInstance);

        bValid = SqlStep(q) ? SqlGetInt(q, 0) : FALSE;
    }
    else if (sFormat == "ipv4")
    {
        bValid = schema_util_RegExpMatch("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", sInstance);
    }
    else if (sFormat == "ipv6")
    {
        bValid = schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}$", sInstance)
              || schema_util_RegExpMatch("^::([0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4}$", sInstance)
              || schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){1,7}:$", sInstance)
              || schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){1}(:[0-9A-Fa-f]{1,4}){1,6}$", sInstance)
              || schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){2}(:[0-9A-Fa-f]{1,4}){1,5}$", sInstance)
              || schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){3}(:[0-9A-Fa-f]{1,4}){1,4}$", sInstance)
              || schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){4}(:[0-9A-Fa-f]{1,4}){1,3}$", sInstance)
              || schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){5}(:[0-9A-Fa-f]{1,4}){1,2}$", sInstance)
              || schema_util_RegExpMatch("^([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}){1}$", sInstance);
    }
    else if (sFormat == "uri")
    {
        bValid = schema_util_RegExpMatch("^[a-zA-Z][a-zA-Z0-9+.-]*:[^\\s]*$", sInstance);
    }
    else if (sFormat == "uri-reference")
    {
        bValid = (sInstance == "") || schema_util_RegExpMatch("^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?$", sInstance);
    }
    else if (sFormat == "iri")
    {
        bValid = schema_util_RegExpMatch("^[\\w\\d\\-._~:/?#\\[\\]@!$&'()*+,;=%]+$", sInstance);
    }
    else if (sFormat == "iri-reference")
    {
        bValid = (sInstance == "")
              || schema_util_RegExpMatch("^[\\w\\d\\-._~:/?#\\[\\]@!$&'()*+,;=%]+$", sInstance)
              || schema_util_RegExpMatch("^[/?#]", sInstance);
    }
    else if (sFormat == "date")
    {
        bValid = schema_util_RegExpMatch("^\\d{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))$", sInstance);
    }
    else if (sFormat == "date-time")
    {
        bValid = schema_util_RegExpMatch("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$", sInstance);
    }
    else if (sFormat == "time")
    {
        bValid = schema_util_RegExpMatch("^\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})?$", sInstance);
    }
    else if (sFormat == "duration")
    {
        bValid = schema_util_RegExpMatch("^P(?!$)(\\d+Y)?(\\d+M)?(\\d+D)?(T(?!$)(\\d+H)?(\\d+M)?(\\d+(\\.\\d+)?S)?)?$", sInstance);
    }
    else if (sFormat == "json-pointer")
    {
        bValid = (sInstance == "") || schema_util_RegExpMatch("^(/([^/~]|~[01])*)*$", sInstance);
    }
    else if (sFormat == "relative-json-pointer")
    {
        bValid = schema_util_RegExpMatch("^(0|[1-9][0-9]*)(#|(/([^/~]|~[01])*)*)$", sInstance);
    }
    else if (sFormat == "uuid")
    {
        bValid = schema_util_RegExpMatch("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", sInstance);
    }
    else if (sFormat == "regex")
    {
        bValid = (GetStringLength(sInstance) > 0);
        
        if (bValid)
        {
            bValid = schema_util_RegExpMatch("^[^\\\\]*(\\\\.[^\\\\]*)*$", sInstance);
        }
    }
    else
    {
        return schema_output_SetError(joOutputUnit, "unsupported format: " + sFormat);
    }

    schema_debug_ExitFunction(__FUNCTION__);
    if (bValid)
        return schema_output_SetAnnotation(joOutputUnit, "format", jSchema);
    else
        return schema_output_SetError(schema_output_SetValid(joOutputUnit, FALSE), "instance does not match format: " + sFormat);
}

/// @todo adding this in as a converter to let us use a pure-sqlite implementation for these
///     numerical checks, not because it's more efficient (it absolutely isn't), but because
///     it allows us to work with 64-bit numbers, which the json-schema test suite assumes
///     are available.  Plus, we may run into these kind of numbers in normal usage, so let's
///     at least give it a shot.
json schema_validate_ConvertNumericValue(json jInstance)
{
    switch (JsonGetType(jInstance))
    {
        case JSON_TYPE_FLOAT:
        case JSON_TYPE_INTEGER:
            return jInstance;
        case JSON_TYPE_STRING:
            return JsonInt(GetStringLength(JsonGetString(jInstance)));
        case JSON_TYPE_ARRAY:
            return JsonInt(JsonGetLength(jInstance));
        case JSON_TYPE_OBJECT:
            return JsonInt(JsonGetLength(JsonObjectKeys(jInstance)));
    }

    return jInstance;
}

json schema_validate_Assertion(string sKeyword, json jInstance, string sOperator, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();

    int nInstanceType = JsonGetType(jInstance);
    if (sKeyword == "minimum" || sKeyword == "maximum" || sKeyword == "exclusiveMinimum" || sKeyword == "exclusiveMaximum" || sKeyword == "multipleOf")
    {
        if (nInstanceType != JSON_TYPE_INTEGER && nInstanceType != JSON_TYPE_FLOAT)
            return joOutputUnit;
    }
    else if (sKeyword == "minLength" || sKeyword == "maxLength")
    {
        if (nInstanceType != JSON_TYPE_STRING)
            return joOutputUnit;
    }
    else if (sKeyword == "minItems" || sKeyword == "maxItems")
    {
        if (nInstanceType != JSON_TYPE_ARRAY)
            return joOutputUnit;
    }
    else if (sKeyword == "minProperties" || sKeyword == "maxProperties")
    {
        if (nInstanceType != JSON_TYPE_OBJECT)
            return joOutputUnit;
    }

    jInstance = schema_validate_ConvertNumericValue(jInstance);

    string s = r"
        SELECT CASE 
            WHEN :op = '>=' THEN i_val >= s_val
            WHEN :op = '<=' THEN i_val <= s_val
            WHEN :op = '>'  THEN i_val > s_val
            WHEN :op = '<'  THEN i_val < s_val
            WHEN :op = '==' THEN i_val = s_val
            WHEN :op = '!=' THEN i_val != s_val
            WHEN :op = '%' THEN (
                ABS(
                    (CAST(i_val AS REAL) / CAST(s_val AS REAL)) - 
                    ROUND(CAST(i_val AS REAL) / CAST(s_val AS REAL))
                ) < 0.000000001
            )
            ELSE 0 
        END
        FROM (
            SELECT 
                json_extract(:instance, '$') as i_val, 
                json_extract(:schema, '$') as s_val
        );
    ";
    sqlquery q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindJson(q, ":instance", jInstance);
    SqlBindJson(q, ":schema", jSchema);
    SqlBindString(q, ":op", sOperator);

    if (SqlStep(q) ? SqlGetInt(q, 0) : FALSE)
        return joOutputUnit;
    else
        return schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), __FUNCTION__ + " (" + sKeyword + ")");
}

/// @private Validates the array "uniqueItems" keyword.
/// @param jaInstance The instance to validate.
/// @param jSchema The schema value for "uniqueItems".
/// @returns An output object containing the validation result.
json schema_validate_UniqueItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "uniqueItems";

    /// @note uniqueItems is ignored for non-array instances.
    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return schema_output_SetAnnotation(joOutputUnit, sKeyword, JsonString("keyword ignored due to instance type"), sSource + " (instance type)");

    if (jSchema == JSON_FALSE)
        return schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource + " (false)");

    if (JsonGetLength(jaInstance) == JsonGetLength(JsonArrayTransform(jaInstance, JSON_ARRAY_UNIQUE)))
        return schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    else
        return schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
}

/// @brief `prefixItems`.  The value of this keyword must be a non-empty array of valid schema.  `prefixItems`
///     is a tuple validation, comparing each item in the instance array against the corresponding schema
///     item from the `prefixItems` array.
/// @note If prefixItems.length > instance.length, excess prefixItem schema are ignored.
/// @note If prefixItems.length < instance.length, excess instance items are not evaluated by `prefixItems`.

/// @brief items.  When the value of this keyword is an array, `items` is a tuple validation, comparing each
///     item in the instance array against the corresponding schema item in the `items` array.
/// @note If items.length > instance.length, excess `items` schema are ignored.
/// @note If items.length < instance.length, excess instance items are not evaluated by `items`.
/// @note Only `items` as an array is handled here since the validation is equivalent to validating
///     `prefixItems`.  For validation when `items` is a schema, see the code section for
///     `items`/`additionalItems` below.

json schema_validate_Tuple(json jaInstance, json jSchema, int bAnnotate = FALSE)
{
    schema_debug_EnterFunction(__FUNCTION__);

    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    int nSchemaLength = JsonGetLength(jSchema);
    if (nSchemaLength > 0)
    {
        json jaEvaluatedItems = JsonArray();
        int i; for (; i < nSchemaLength && i < JsonGetLength(jaInstance); i++)
        {
            schema_scope_PushSchemaPath(IntToString(i));
            schema_scope_PushInstancePath(IntToString(i));

            json joResult = schema_core_Validate(JsonArrayGet(jaInstance, i), JsonArrayGet(jSchema, i));
            joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);
            jaEvaluatedItems = JsonArrayInsert(jaEvaluatedItems, JsonInt(i));

            schema_scope_PopInstancePath();
            schema_scope_PopSchemaPath();
        }

        if (bAnnotate)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems, sSource);
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @brief items.  The value of `items` must be a valid schema.  Validation only occurs against
///     instance items that have not been previously evaluated by `prefixItems`.  For all reamining
///     unevaluated instance items, each instance item is validated against the `items` schema.
/// @note If prefixItems.length > instance.length, `items` schema is ignored.

/// @brief additionalItems.  The value of `additionalItems` must be a valid schema.  Validation
///     only occurs against instance items that have not been previously evaluated by `items` (array).
///     For all remaining unevaluated instance items, each instance item is validated against the
///     `additionalItems` schema.
/// @note If additionalItems = true, all unevaluated instance items are validated.
/// @note If additionalItems = false, validation of unevaluated items is disallowed and the instace
///     fails validation.
/// @note additionalItems = {} is functionally identical to additionlItems = true.

json schema_validate_Uniform(json jaInstance, json jSchema, int nTupleLength, int bAnnotate = FALSE)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json joOutputUnit = schema_output_GetOutputUnit();

    int nInstanceLength = JsonGetLength(jaInstance);
    if (nInstanceLength > nTupleLength)
    {
        string sSource = __FUNCTION__;
        json jaEvaluatedItems = JsonArray();

        if (jSchema == JsonObject())
            jSchema = JSON_TRUE;

        int nSchemaType = JsonGetType(jSchema);
        if (nSchemaType == JSON_TYPE_BOOL)
        {
            json joItemOutputUnit = schema_output_GetOutputUnit();
            int i; for (i = nTupleLength; i < nInstanceLength; i++)
            {
                schema_scope_PushInstancePath(IntToString(i));

                if (jSchema == JSON_TRUE)
                    joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joItemOutputUnit, sSource);
                else
                    joOutputUnit = schema_output_InsertError(joOutputUnit, joItemOutputUnit, sSource);

                if (bAnnotate)
                    jaEvaluatedItems = JsonArrayInsert(jaEvaluatedItems, JsonInt(i));

                schema_scope_PopInstancePath();
            }
        }
        else if (nSchemaType == JSON_TYPE_OBJECT)
        {
            int i; for (i = nTupleLength; i < nInstanceLength; i++)
            {
                schema_scope_PushInstancePath(IntToString(i));

                json joResult = schema_core_Validate(JsonArrayGet(jaInstance, i), jSchema);
                joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);

                if (bAnnotate)
                    jaEvaluatedItems = JsonArrayInsert(jaEvaluatedItems, JsonInt(i));

                schema_scope_PopInstancePath();
            }
        }

        if (bAnnotate)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems, sSource);
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @brief `prefixItems`.  The value of this keyword must be a non-empty array of valid schema.  `prefixItems`
///     is a tuple validation, comparing each item in the instance array against the corresponding schema
///     item from the `prefixItems` array.
/// @note If prefixItems.length > instance.length, excess prefixItem schema are ignored.
/// @note If prefixItems.length < instance.length, excess instance items are not evaluated by `prefixItems`.

/// @brief items.  When the value of this keyword is an array, `items` is a tuple validation, comparing each
///     item in the instance array against the corresponding schema item in the `items` array.
/// @note If items.length > instance.length, excess `items` schema are ignored.
/// @note If items.length < instance.length, excess instance items are not evaluated by `items`.
/// @note Only `items` as an array is handled here since the validation is equivalent to validating
///     `prefixItems`.  For validation when `items` is a schema, see the code section for
///     `items`/`additionalItems` below.

json schema_validate_Items(json jInstance, json jaPrefixItems, json jItems, json jAdditionalItems, int bAnnotate = FALSE)
{    
    schema_debug_EnterFunction(__FUNCTION__);

    json jaOutput = JsonArray();
    string sFunction = __FUNCTION__;
    string sSource = sFunction;

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return jaOutput;
    }

    /// @note prefixItems
    string sKeyword = "prefixItems";
    if (JsonGetType(jaPrefixItems) == JSON_TYPE_ARRAY)
    {
        schema_scope_PushSchemaPath(sKeyword);
        json joResult = schema_validate_Tuple(jInstance, jaPrefixItems, bAnnotate);
        jaOutput = JsonArrayInsert(jaOutput, joResult);
        schema_scope_PopSchemaPath();
    }

    /// @note items
    sKeyword = "items";
    int nItemsType = JsonGetType(jItems);
    if (nItemsType != JSON_TYPE_NULL)
    {
        schema_scope_PushSchemaPath(sKeyword);
        
        json joResult;
        if (nItemsType == JSON_TYPE_ARRAY)
        {
            joResult = schema_validate_Tuple(jInstance, jItems, bAnnotate);
        }
        else if (nItemsType == JSON_TYPE_OBJECT || nItemsType == JSON_TYPE_BOOL)
        {
            int nTupleLength = 0;
            if (JsonGetType(jaPrefixItems) == JSON_TYPE_ARRAY)
                nTupleLength = JsonGetLength(jaPrefixItems);

            joResult = schema_validate_Uniform(jInstance, jItems, nTupleLength, bAnnotate);
        }

        jaOutput = JsonArrayInsert(jaOutput, joResult);
        schema_scope_PopSchemaPath();
    }

    /// @note additionalItems
    sKeyword = "additionalItems";
    int nAdditionalItemsType = JsonGetType(jAdditionalItems);
    if (nAdditionalItemsType != JSON_TYPE_NULL)
    {
        if (JsonGetType(jItems) == JSON_TYPE_ARRAY)
        {
            schema_scope_PushSchemaPath(sKeyword);

            int nTupleLength = JsonGetLength(jItems);
            json joResult = schema_validate_Uniform(jInstance, jAdditionalItems, nTupleLength, bAnnotate);

            jaOutput = JsonArrayInsert(jaOutput, joResult);
            schema_scope_PopSchemaPath();
        }
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return jaOutput;
}

/// @brief contains.  The value of `contains` must be a valid schema.  Validation occurs
///     against all instance items, including those previously evaluated by `items` and
///     `prefixItems`.  An instance array is valid against `contains` if at least one of the
///     instance array's items is valid against the `contains` schema.
/// @note If contains = true, the instance array is considered valid if the instance array
///     has at least `minContains` items and no more than `maxContains` items.  All instance
///     items are considered evaluated.
/// @note If contains = false, the instance array is considered invalid (unless minContains = 0)
///     and no instance items are considered evaluated.
/// @note Instance items which successfully validate against the `contains` schema are
///     considered evaluated; instance items that do not validate against the `contains`
///     schema are not considered evaluated.

/// @brief minContains.  The value of `minContains` must be a non-negative integer.  This
///     keyword is ignored if `contains` is not present in the same schema object.  To
///     validate against `minContains`, the instance array must have at least `minContains`
///     items that are valid against the `contains` schema.
/// @note If minContains = 0, the instance array is considered valid against the `contains`
///     schema, even if no instance items can be validated against the `contains` schema or
///     if the instance array is empty.
/// @note If `minContains` is ommitted, a default value of 1 is used.

/// @brief maxContains.  The value of `maxContains` must be a non-negative integer.  This
///     keyword is ignored if `contains` is not present in the same schema object.  To
///     validate against `maxContains`, the instance array must have no more than `maxContains`
///     items that are valid against the `contains` schema.
/// @note If maxContains = 0 && instance.length = 0, the instance is considered valid against
///     the `contains` schema.
json schema_validate_Contains(json jaInstance, json jContains, json jiMinContains, json jiMaxContains, int bAnnotate)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json jaOutput = JsonArray();
    string sSource = __FUNCTION__;

    /// @todo
    ///      temp fix to see about passing failing contains tests...
    ///     does removing this cause any failures?

    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return jaOutput;
    }
    /// ---

    string sKeyword = "contains";
    int nKeywordType = JsonGetType(jContains);
    if (nKeywordType != JSON_TYPE_NULL)
    {
        schema_scope_PushSchemaPath(sKeyword);

        json joOutputUnit = schema_output_GetOutputUnit();
        json jaEvaluatedItems = JsonArray();
        
        int nMinContains = JsonGetType(jiMinContains) != JSON_TYPE_NULL ? JsonGetInt(jiMinContains) : -1;
        int nMaxContains = JsonGetType(jiMaxContains) != JSON_TYPE_NULL ? JsonGetInt(jiMaxContains) : -1;

        int bContains, nInstanceLength = JsonGetLength(jaInstance);
        
        if (jContains == JsonObject() || nMinContains == 0)
        // if (jContains == JsonObject())
            jContains = JSON_TRUE;

        if (nKeywordType == JSON_TYPE_BOOL)
        {
            /// @note The following conditions satisfy validation for contains = true
            ///     and contains = false
            if ((
                (nMinContains == 0) ||
                (nMaxContains == 0 && nInstanceLength == 0)
                ) ||
                (
                    /// @note If contains = true, the following additional conditions satisfy validation:
                    ///     - instance.length >= 1; `[min|max]Contains` is not specified
                    ///     - minContains <= instance.length <= maxContains
                    ///     - minContains <= instance.length; `maxContains` is not specified
                    ///     - 1 <= instance.length <= maxContains; `minContains` is not specified
                    (jContains == JSON_TRUE && 
                        (
                            (nInstanceLength >= 1 && nMinContains == -1 && nMaxContains == -1) ||
                            (nMinContains > -1 && nMaxContains > -1 && nInstanceLength >= nMinContains && nInstanceLength <= nMaxContains) ||
                            (nMinContains > -1 && nMaxContains == -1 && nInstanceLength >= nMinContains) ||
                            (nMaxContains > -1 && nMinContains == -1 && nInstanceLength >= 1 && nInstanceLength <= nMaxContains)
                        )
                    )
                )
            )
            {
                if (nInstanceLength > 0)
                {
                    int i; for (; i < nInstanceLength; i++)
                        jaEvaluatedItems = JsonArrayInsert(jaEvaluatedItems, JsonInt(i));
                }

                bContains = TRUE;
            }

            json joItemOutputUnit = schema_output_GetOutputUnit();
            int i; for (i = 0; i < nInstanceLength; i++)
            {
                schema_scope_PushInstancePath(IntToString(i));

                if (JsonGetLength(jaEvaluatedItems) > 0)
                    joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joItemOutputUnit, sSource + "[BOOL]");
                else
                    joOutputUnit = schema_output_InsertError(joOutputUnit, joItemOutputUnit, sSource + "[BOOL]");

                schema_scope_PopInstancePath();
            }

            joOutputUnit = schema_output_SetValid(joOutputUnit, bContains);
        }
        else if (nKeywordType == JSON_TYPE_OBJECT)
        {
            int i; for (; i < nInstanceLength; i++)
            {
                schema_scope_PushInstancePath(IntToString(i));

                json joResult = schema_core_Validate(JsonArrayGet(jaInstance, i), jContains);
                if (schema_output_GetValid(joResult))
                    jaEvaluatedItems = JsonArrayInsert(jaEvaluatedItems, JsonInt(i));

                /// @note A instance item that fails validations of a `contains` schema does not cause
                ///     the instance array to fail validation.  Validation results for `contains` schema
                ///     validation are always annotations.
                joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joResult, sSource + "[OBJECT/Inner]");
                schema_scope_PopInstancePath();
            }

            int nMatches = JsonGetLength(jaEvaluatedItems);
            if (
                (nMatches < (nMinContains == -1 ? 1 : nMinContains)) ||
                (nMaxContains != -1 && nMatches > nMaxContains)
            )
            {
                joOutputUnit = schema_output_SetValid(joOutputUnit, FALSE);
            }
        }

        if (bAnnotate)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems, sSource + "[OBJECT/outer]");

        schema_scope_PopSchemaPath();
        jaOutput = JsonArrayInsert(jaOutput, joOutputUnit);

        json jaKeywords = JsonParse(r"[
            ""minContains"",
            ""maxContains""
        ]");

        int i; for (; i < JsonGetLength(jaKeywords); i++)
        {
            string sOperator, sKeyword = JsonGetString(JsonArrayGet(jaKeywords, i));

            json jKeyword = JsonNull();
            if (sKeyword == "minContains")
            {
                jKeyword = jiMinContains;
                sOperator = ">=";
            }
            else
            {
                jKeyword = jiMaxContains;
                sOperator = "<=";
            }

            nKeywordType = JsonGetType(jKeyword);
            if (nKeywordType == JSON_TYPE_INTEGER || nKeywordType == JSON_TYPE_FLOAT)
            {
                schema_scope_PushSchemaPath(sKeyword);
                joOutputUnit = schema_validate_Assertion(sKeyword, JsonInt(JsonGetLength(jaEvaluatedItems)), sOperator, jKeyword);
                schema_scope_PopSchemaPath();

                jaOutput = JsonArrayInsert(jaOutput, joOutputUnit);
            }
        }
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return jaOutput;
}

/// @private Validates the object "required" keyword.
/// @param joInstance The object instance to validate.
/// @param jSchema The schema value for "required".
/// @returns An output object containing the validation result.
json schema_validate_Required(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "required";

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaMissingProperties = JsonArray();
    //json jaInstanceKeys = JsonObjectKeys(joInstance);
    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        json jProperty = JsonArrayGet(jSchema, i);
        //if (JsonFind(jaInstanceKeys, jProperty) == JsonNull())
        if (!schema_util_HasKey(joInstance, JsonGetString(jProperty)))
            jaMissingProperties = JsonArrayInsert(jaMissingProperties, jProperty);
    }

    if (JsonGetLength(jaMissingProperties) > 0)
        return schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    else
        return schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
}

/// @brief Validates the object "dependentRequired" keyword.
/// @param joInstance The object instance to validate.
/// @param joDependentRequired The schema value for "dependentRequired".
/// @returns An output object containing the validation result.
json schema_validate_DependentRequired(json joInstance, json jSchema)
{
    string sKeyword = "dependentRequired";
    json joOutputUnit = schema_output_GetOutputUnit(sKeyword);
    string sSource = __FUNCTION__;
    
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaInstanceKeys = JsonObjectKeys(joInstance);
    json jaSchemaKeys = JsonObjectKeys(jSchema);
    
    int i; for (; i < JsonGetLength(jaSchemaKeys); i++)
    {
        json jProperty = JsonArrayGet(jaSchemaKeys, i);

        // Check if the property exists in the instance (robustly)
        if (schema_util_HasKey(joInstance, JsonGetString(jProperty)))
        {
            json jaRequired = JsonObjectGet(jSchema, JsonGetString(jProperty));
            json jaMissing = JsonArray();
            
            int j; for (; j < JsonGetLength(jaRequired); j++)
            {
                json jRequiredKey = JsonArrayGet(jaRequired, j);
                // Check if the required dependency exists in the instance (robustly)
                if (!schema_util_HasKey(joInstance, JsonGetString(jRequiredKey)))
                    jaMissing = JsonArrayInsert(jaMissing, jRequiredKey);
            }

            if (JsonGetLength(jaMissing) > 0)
                return schema_output_SetError(joOutputUnit, "Dependency failed: " + JsonGetString(jProperty) + " requires " + JsonDump(jaMissing), sSource);
        }
    }

    return joOutputUnit;
}

/// @private Validates the object `propertyNames` keyword.
/// @param joInstance the object instance to validate.
/// @param jSchema The schema value for `propertyNames`.
/// @returns An output unit containing the validation result.
json schema_validate_PropertyNames(json joInstance, json jSchema)
{
    string sKeyword = "propertyNames";
    json joOutputUnit = schema_output_GetOutputUnit(sKeyword);
    string sSource = __FUNCTION__;
    
       
    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaInstanceKeys = JsonObjectKeys(joInstance);
    int nInstanceKeys = JsonGetLength(jaInstanceKeys);

    int nKeywordType = JsonGetType(jSchema);
    if (nKeywordType == JSON_TYPE_BOOL)
    {
        if (jSchema == JSON_FALSE && nInstanceKeys > 0)
            joOutputUnit = schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
        else
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    }
    else if (nKeywordType == JSON_TYPE_OBJECT)
    {
        if (joInstance == JsonObject())
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
        else
        {
            int i; for (; i < nInstanceKeys; i++)
            {
                string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                schema_scope_PushInstancePath(sInstanceKey);

                json joResult = schema_core_Validate(JsonString(sInstanceKey), jSchema);
                joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);

                schema_scope_PopInstancePath();
            }
        }
    }

    return joOutputUnit;
}

/// @brief Validates interdependent object keywords "properties", "patternProperties",
///     "additionalProperties", "dependencies", "dependentSchemas".
/// @param joInstance The object instance to validate.
/// @param joProperties The schema value for "properties".
/// @param joPatternProperties The schema value for "patternProperties".
/// @param jAdditionalProperties The schema value for "additionalProperties".
/// @param joDependencies The schema value for "dependencies".
/// @param joDependentSchemas The schema value for "dependentSchemas".
/// @returns An output object containing the validation result.
json schema_validate_Object(
    json joInstance,
    json joProperties,
    json joPatternProperties,
    json jAdditionalProperties,
    json joDependencies,
    json joDependentSchemas,
    int bAnnotate = FALSE
)
{
    schema_debug_EnterFunction(__FUNCTION__);

    json jaOutput = JsonArray();
    string sFunction = __FUNCTION__;
    string sSource = sFunction;

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
    {
        schema_debug_ExitFunction(__FUNCTION__);
        return jaOutput;
    }

    /// @todo
    ///    [ ] add instance-type check function here.

    json jaInstanceKeys = JsonObjectKeys(joInstance);
    int nInstanceKeys = JsonGetLength(jaInstanceKeys);

    /// @brief properties.  The schema value of `properties` must be an object and all values within
    ///     must be valid schema.  For each property name that appears in both the instance and
    ///     schema, the child instance is validated against the corresponding schema.
    /// @note If properties = {}, the validation automatically succeeds.

    string sKeyword = "properties";
    string sAnnotationKey = "evaluatedProperties";
        
    if (JsonGetType(joProperties) == JSON_TYPE_OBJECT)
    {
        schema_scope_PushSchemaPath(sKeyword);

        json joOutputUnit = schema_output_GetOutputUnit(sKeyword);
        
        if (joProperties == JsonObject())
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sKeyword, joProperties, sSource);
        else
        {
            json jaPropertyKeys = JsonObjectKeys(joProperties);
            json jaEvaluatedProperties = JsonArray();

            int i; for (; i < nInstanceKeys; i++)
            {
                string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                schema_scope_PushInstancePath(sInstanceKey);

                json joPropertySchema = schema_util_JsonObjectGet(joProperties, sInstanceKey);
                if (JsonGetType(joPropertySchema) != JSON_TYPE_NULL)
                {
                    schema_scope_PushSchemaPath(sInstanceKey);

                    json joResult = schema_core_Validate(schema_util_JsonObjectGet(joInstance, sInstanceKey), joPropertySchema);
                    joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);                

                    if (bAnnotate)
                        jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sInstanceKey));
                    
                    schema_scope_PopSchemaPath();
                }
                
                schema_scope_PopInstancePath();
            }

            if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties, sSource);
        }
        
        jaOutput = JsonArrayInsert(jaOutput, joOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief patternProperties.  The schema value of `patternProperties` must be an object.  The schema
    ///     property names should be valid ecma-262 regex patterns.  For each property name in the
    ///     instance that matches *any* regex pattern in the schema's property names, the child instance
    ///     is validated aginst the corresponding schema.
    /// @note If instance = {}, the validation automatically succeeds.
    /// @note if patternProperties = {}, the validation automatically succeeds.
    /// @note All instance property names that match schema property name regex patterns are considered
    ///     evaluated, whether or not they pass validation.
    /// @warning Evaluating valid regex patterns is beyond the scope of this system.

    sKeyword = "patternProperties";
    if (JsonGetType(joPatternProperties) == JSON_TYPE_OBJECT)
    {
        schema_scope_PushSchemaPath(sKeyword);

        json joOutputUnit = schema_output_GetOutputUnit(sKeyword);
        json jaPatternKeys = JsonObjectKeys(joPatternProperties);

        if (nInstanceKeys == 0 || joPatternProperties == JsonObject())
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sKeyword, joPatternProperties, sSource);
        else
        {
            json jaEvaluatedProperties = JsonArray();

            int i; for (; i < nInstanceKeys; i++)
            {
                string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                schema_scope_PushInstancePath(sInstanceKey);

                int j; for (; j < JsonGetLength(jaPatternKeys); ++j)
                {
                    string sPattern = JsonGetString(JsonArrayGet(jaPatternKeys, j));
                    schema_scope_PushSchemaPath(sPattern);

                    if (schema_util_RegExpMatch(sPattern, sInstanceKey))
                    {
                        json joPatternSchema = schema_util_JsonObjectGet(joPatternProperties, sPattern);
                        if (JsonGetType(joPatternSchema) != JSON_TYPE_NULL)
                        {
                            json joResult = schema_core_Validate(schema_util_JsonObjectGet(joInstance, sInstanceKey), joPatternSchema);
                            joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);

                            if (bAnnotate)
                                jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sInstanceKey));
                        }
                    }

                    schema_scope_PopSchemaPath();
                }

                schema_scope_PopInstancePath();
            }

            if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties);
        }

        jaOutput = JsonArrayInsert(jaOutput, joOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief additionalProperties. The value of `additionalProperties` must be a valid schema.  Validation only
    ///     occurs against instance property names which were not evaluated by `properties` or `patternProperties`.
    /// @note If additionalProperties = true, all unevaluated instance property names are considered to have passed
    ///     validation and are considered evaluated.
    /// @note If additionalProperties = false, all unevaluated instance property names are considered to have failed
    ///     validation are are considered evaluated.
    /// @note If additionalProperties = {}, unevaluated instance property names are not validated and are still
    ///     considered unevaluated.

    sKeyword = "additionalProperties";

    int nKeywordType = JsonGetType(jAdditionalProperties);
    if (nKeywordType == JSON_TYPE_OBJECT || nKeywordType == JSON_TYPE_BOOL)
    {
        schema_scope_PushSchemaPath(sKeyword);
        json joOutputUnit = schema_output_GetOutputUnit(sKeyword);
        
        json jaUnevaluatedProperties = schema_output_GetUnevaluatedProperties(jaOutput, jaInstanceKeys);
        
        json jaEvaluatedProperties = JsonArray();

        if (jAdditionalProperties == JsonObject())
            jAdditionalProperties = JSON_TRUE;

        nKeywordType = JsonGetType(jAdditionalProperties);

        if (nKeywordType == JSON_TYPE_BOOL)
        {
            if (jAdditionalProperties == JSON_FALSE && JsonGetLength(jaUnevaluatedProperties) > 0)
                joOutputUnit = schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource + "[additionalProperties]");
            else if (jAdditionalProperties == JSON_TRUE)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sKeyword, jAdditionalProperties, sSource);

            if (bAnnotate && jAdditionalProperties == JSON_TRUE)
                jaEvaluatedProperties = jaUnevaluatedProperties;
        }
        else if (nKeywordType == JSON_TYPE_OBJECT)
        {
            int i; for (; i < JsonGetLength(jaUnevaluatedProperties); i++)
            {
                string sUnevaluatedKey = JsonGetString(JsonArrayGet(jaUnevaluatedProperties, i));
                schema_scope_PushInstancePath(sUnevaluatedKey);

                json joInstanceChild = schema_util_JsonObjectGet(joInstance, sUnevaluatedKey);
                if (JsonGetType(joInstanceChild) != JSON_TYPE_NULL)
                {
                    json joResult = schema_core_Validate(joInstanceChild, jAdditionalProperties);
                    joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);

                    if (bAnnotate)
                        jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sUnevaluatedKey));
                }

                schema_scope_PopInstancePath();
            }
        }
        
        if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties, sSource);

        jaOutput = JsonArrayInsert(jaOutput, joOutputUnit);
        schema_scope_PopSchemaPath();
    }

    // 4. dependentSchemas/dependencies

    json jSchema = JsonNull();
    if (JsonGetType(joDependencies) == JSON_TYPE_OBJECT)
    {
        sKeyword = "dependencies";
        jSchema = joDependencies;
    }
    else if (JsonGetType(joDependentSchemas) == JSON_TYPE_OBJECT)
    {
        sKeyword = "dependentSchemas";
        jSchema = joDependentSchemas;
    }

    if (JsonGetType(jSchema) == JSON_TYPE_OBJECT)
    {
        schema_scope_PushSchemaPath(sKeyword);

        if (jSchema == JsonObject())
            jaOutput = JsonArrayInsert(jaOutput, schema_output_GetOutputUnit());
        else if (JsonGetType(jSchema) == JSON_TYPE_OBJECT)
        {
            json joOutputUnit = schema_output_GetOutputUnit(sKeyword);

            json jaSchemaKeys = JsonObjectKeys(jSchema);
            int nSchemaKeys = JsonGetLength(jaSchemaKeys);
            
            json jaEvaluatedProperties = JsonArray();

            int i; for (; i < nSchemaKeys; i++)
            {
                string sSchemaKey = JsonGetString(JsonArrayGet(jaSchemaKeys, i));
                schema_scope_PushSchemaPath(sSchemaKey);

                // Use schema_util_HasKey to check if the instance has the key
                if (schema_util_HasKey(joInstance, sSchemaKey))
                {
                    json joSchema = JsonObjectGet(jSchema, sSchemaKey);
                    int nSchemaType = JsonGetType(joSchema);
                    if (nSchemaType == JSON_TYPE_BOOL)
                    {
                        if (joSchema == JSON_TRUE)
                        {
                            json joOutput = schema_output_SetAnnotation(schema_output_GetOutputUnit(), sSchemaKey, joSchema, sSource);
                            joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joOutput);
                        }
                        else
                        {
                            json joOutput = schema_output_SetError(schema_output_GetOutputUnit(), sSchemaKey + " not allowed", sSource);
                            joOutputUnit = schema_output_InsertError(joOutputUnit, joOutput);
                        }
                    }
                    else
                    {
                        json joResult;
                        if (nSchemaType == JSON_TYPE_ARRAY)
                            joResult = schema_validate_DependentRequired(joInstance, joSchema);
                        else if (nSchemaType == JSON_TYPE_OBJECT)
                            joResult = schema_core_Validate(joInstance, joSchema);
                
                        joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);
                    }

                    if (bAnnotate)
                        jaEvaluatedProperties = JsonArrayInsert(jaEvaluatedProperties, JsonString(sSchemaKey));
                }

                schema_scope_PopSchemaPath();
            }
            
            if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties, sSource);

            jaOutput = JsonArrayInsert(jaOutput, joOutputUnit);
        }
        
        schema_scope_PopSchemaPath();
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return jaOutput;
}

json schema_validate_Unevaluated(json jInstance, json joSchema, json joOutputUnit)
{
    /// @brief unevaluatedItems.  The value of `unevaluatedItems` must be a valid schema.  Validation
    ///     only occurs against instance items that have not been previously evaluated by `prefixItems`,
    ///     `items` or `contains`.  For all remaining unevaluated instance items, each instance item is
    ///     validated against the `unevaluatedItems` schema.
    /// @note if unevaluatedItems = true, all unevaluated instance items are validated.
    /// @note if unevaluatedItems = false, validation of unevaluated items is disallowed and the instance
    ///     fails validation.
    /// @note unevaluatedItems = {} is functionally identical to unevaluatedItems = true.

    json jaKeywords = JsonParse(r"[
        ""unevaluatedProperties"",
        ""unevaluatedItems""
    ]");

    json jaAnnotationKeys = JsonParse(r"[
        ""evaluatedProperties"",
        ""evaluatedItems""
    ]");

    string sSource = __FUNCTION__;

    int i; for (; i < JsonGetLength(jaKeywords); i++)
    {
        string sError, sKeyword = JsonGetString(JsonArrayGet(jaKeywords, i));
        json jKeywordSchema = JsonObjectGet(joSchema, sKeyword);

        int nKeywordType = JsonGetType(jKeywordSchema);
        if (nKeywordType == JSON_TYPE_NULL)
            continue;
        else
        {
            string sAnnotationKey = JsonGetString(JsonArrayGet(jaAnnotationKeys, i));
            schema_scope_PushSchemaPath(sKeyword);

            json jaUnevaluatedKeys;
            json joOutput = schema_output_GetOutputUnit(sKeyword);

            int nInstanceType = JsonGetType(jInstance);
            if (nInstanceType == JSON_TYPE_ARRAY)
                jaUnevaluatedKeys = schema_output_GetUnevaluatedItems(joOutputUnit, jInstance);
            else if (nInstanceType == JSON_TYPE_OBJECT)
                jaUnevaluatedKeys = schema_output_GetUnevaluatedProperties(joOutputUnit, jInstance);

            if (JsonGetLength(jaUnevaluatedKeys) > 0)
            {
                joOutput = schema_output_SetAnnotation(joOutput, sAnnotationKey, jaUnevaluatedKeys, sSource);
                if (nKeywordType == JSON_TYPE_BOOL)
                {
                    joOutput = schema_output_SetAnnotation(joOutput, sKeyword, jKeywordSchema);

                    if (jKeywordSchema == JSON_FALSE)
                        joOutput = schema_output_SetError(joOutput, sAnnotationKey + " disallowed", sSource);
                }
                else if (nKeywordType == JSON_TYPE_OBJECT)
                {
                    if (jKeywordSchema != JsonObject())
                    {
                        int nInstanceType = JsonGetType(jInstance);

                        int i; for (; i < JsonGetLength(jaUnevaluatedKeys); i++)
                        {
                            json jUnevaluatedKey = JsonArrayGet(jaUnevaluatedKeys, i);
                            string sUnevaluatedKey = JsonGetString(jUnevaluatedKey);

                            schema_scope_PushInstancePath(sUnevaluatedKey);

                            json jChild;
                            if (nInstanceType == JSON_TYPE_ARRAY)
                                jChild = JsonArrayGet(jInstance, JsonGetInt(jUnevaluatedKey));
                            else if (nInstanceType == JSON_TYPE_OBJECT)
                                jChild = schema_util_JsonObjectGet(jInstance, sUnevaluatedKey);

                            json joResult = schema_core_Validate(jChild, jKeywordSchema);
                            joOutput = schema_output_InsertResult(joOutput, joResult, sSource);

                            schema_scope_PopInstancePath();
                        }
                    }
                }
            }

            joOutputUnit = schema_output_InsertResult(joOutputUnit, joOutput, sSource);
            schema_scope_PopSchemaPath();
        }
    }

    return joOutputUnit;
}

/// @brief Validates the applicator "not" keyword.
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "not".
/// @returns An output object containing the validation result.
json schema_validate_Not(json jInstance, json jSchema)
{
    //json joOutputUnit = schema_output_GetOutputUnit();
    //string sSource = __FUNCTION__;

    json joResult = schema_core_Validate(jInstance, jSchema);
    return schema_output_SetValid(joResult, !schema_output_GetValid(joResult));

    //json joResult = schema_core_Validate(jInstance, jSchema);
    //joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);

    //return joOutputUnit;
}

/// @brief Validates the applicator "allOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "allOf".
/// @returns An output object containing the validation result.
json schema_validate_AllOf(json jInstance, json jSchema, int bAnnotate = FALSE)
{
    schema_debug_EnterFunction(__FUNCTION__);

    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        if (schema_output_GetValid(joResult))
        {
            schema_scope_PushContext("SCOPE_CONTEXT_EVALUATED_PROPERTIES", schema_output_GetEvaluatedProperties(joResult));
            schema_scope_PushContext("SCOPE_CONTEXT_EVALUATED_ITEMS", schema_output_GetEvaluatedItems(joResult));
        }

        joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);
        schema_scope_PopSchemaPath();
    }

    if (bAnnotate && schema_output_GetValid(joOutputUnit))
    {
        json jaEvaluatedKeys = schema_scope_GetContext("SCHEMA_CONTEXT_EVALUATED_PROPERTIES");
        if (JsonGetLength(jaEvaluatedKeys) > 0)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", jaEvaluatedKeys);

        jaEvaluatedKeys = schema_scope_GetContext("SCHEMA_CONTEXT_EVALUATED_ITEMS");
        if (JsonGetLength(jaEvaluatedKeys) > 0)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedKeys);
    }

    schema_scope_PopContext();
    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @brief Validates the applicator "anyOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "anyOf".
/// @returns An output object containing the validation result.
json schema_validate_AnyOf(json jInstance, json jSchema, int bAnnotate = FALSE)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaResults = JsonArray();

    string sSource = __FUNCTION__;

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        jaResults = JsonArrayInsert(jaResults, joResult);

        schema_scope_PopSchemaPath();
    }

    json jaEvaluatedProperties = JsonArray();
    json jaEvaluatedItems = JsonArray();

    for (i = 0; i < JsonGetLength(jaResults); i++)
    {
        json joResult = JsonArrayGet(jaResults, i);
        if (schema_output_GetValid(joResult))
        {
            if (bAnnotate)
            {
                jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(joResult));
                jaEvaluatedItems = schema_scope_MergeArrays(jaEvaluatedItems, schema_output_GetEvaluatedItems(joResult));
            }

            joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joResult, sSource);
        }
        else
            joOutputUnit = schema_output_InsertError(joOutputUnit, JsonArrayGet(jaResults, i), sSource);
    }

    if (bAnnotate)
    {
        if (JsonGetLength(jaEvaluatedProperties) > 0)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", jaEvaluatedProperties);

        if (JsonGetLength(jaEvaluatedItems) > 0)
            joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems);
    }

    return schema_output_SetValid(joOutputUnit, JsonGetLength(JsonObjectGet(joOutputUnit, "annotations")) > 0);
}

/// @brief Validates the applicator "oneOf" keyword
/// @param jInstance The instance to validate.
/// @param jSchema The schema value for "oneOf".
/// @returns An output object containing the validation result.
json schema_validate_OneOf(json jInstance, json jSchema, int bAnnotate = FALSE)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaResults = JsonArray();
    string sSource = __FUNCTION__;

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);
        
        if (schema_output_GetValid(joResult))
            jaResults = JsonArrayInsert(jaResults, joResult);

        schema_scope_PopSchemaPath();
    }

    if (JsonGetLength(jaResults) == 1)
    {
        json joResult = JsonArrayGet(jaResults, 0);

        if (bAnnotate)
        {
            json jaEvaluatedKeys = schema_output_GetEvaluatedProperties(joResult);
            if (JsonGetLength(jaEvaluatedKeys) > 0)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", schema_output_GetEvaluatedProperties(joResult));
            
            jaEvaluatedKeys = schema_output_GetEvaluatedItems(joResult);
            if (JsonGetLength(jaEvaluatedKeys) > 0)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", schema_output_GetEvaluatedItems(joResult));
        }
    }

    return schema_output_SetValid(joOutputUnit, JsonGetLength(jaResults) == 1);
}

/// @brief Validates interdependent applicator keywords "if", "then", "else".
/// @param joInstance The object instance to validate.
/// @param joIf The schema value for "if".
/// @param joThen The schema value for "then".
/// @param joElse The schema value for "else".
/// @returns An output object containing the validation result.
json schema_validate_If(json jInstance, json joIf, json joThen, json joElse, int bAnnotate = FALSE)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    if (JsonGetType(joIf) == JSON_TYPE_NULL)
        return JsonNull();

    if (joIf == JsonObject())
        joIf = JSON_TRUE;

    string sKeyword = "if";
    schema_scope_PushSchemaPath(sKeyword);

    int bIf, nKeywordType = JsonGetType(joIf);
    if (nKeywordType == JSON_TYPE_BOOL)
    {
        joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, schema_output_GetOutputUnit());
        bIf = JsonGetInt(joIf);
    }
    else if (nKeywordType == JSON_TYPE_OBJECT)
    {
        json joResult = schema_core_Validate(jInstance, joIf);
        joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joResult, sSource);

        bIf = schema_output_GetValid(joResult);
    }

    schema_scope_PopSchemaPath();

    json jSchema = bIf ? joThen : joElse;
    sKeyword = bIf ? "then" : "else";

    schema_scope_PushSchemaPath(sKeyword);

    if (jSchema == JsonObject())
        jSchema = JSON_TRUE;

    int nSchemaType = JsonGetType(jSchema);
    if (nSchemaType == JSON_TYPE_BOOL)
    {
        json joOutput = schema_output_GetOutputUnit(sKeyword);

        if (jSchema == JSON_TRUE)
            joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, joOutput);
        else if (jSchema == JSON_FALSE)
            joOutputUnit = schema_output_InsertError(joOutputUnit, joOutput);
    }
    else if (nSchemaType == JSON_TYPE_OBJECT)
    {
        json joResult = schema_core_Validate(jInstance, jSchema);
        joOutputUnit = schema_output_InsertResult(joOutputUnit, joResult, sSource);

        if (bAnnotate && schema_output_GetValid(joResult))
        {
            json jaEvaluatedKeys = schema_output_GetEvaluatedProperties(joResult);
            if (JsonGetLength(jaEvaluatedKeys) > 0)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", schema_output_GetEvaluatedProperties(joResult));
            
            jaEvaluatedKeys = schema_output_GetEvaluatedItems(joResult);
            if (JsonGetLength(jaEvaluatedKeys) > 0)
                joOutputUnit = schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", schema_output_GetEvaluatedItems(joResult));
        }
    }

    schema_scope_PopSchemaPath();
    return joOutputUnit;
}

/// @private Recursively map all $ids in the schema to their schema objects.
/// @param joSchema The schema to map.
/// @param sBaseURI The current base URI.
/// @param joMap The map object (URI -> Schema).
/// @returns The updated map object.
json schema_util_MapIDs(json joSchema, string sBaseURI, json joMap)
{
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
        return joMap;

    string sID = JsonGetString(JsonObjectGet(joSchema, "$id"));
    if (sID == "")
        sID = JsonGetString(JsonObjectGet(joSchema, "id"));

    if (sID != "")
    {
        sBaseURI = schema_reference_ResolveURI(sBaseURI, sID);
        joMap = JsonObjectSet(joMap, sBaseURI, joSchema);
    }

    json jaKeys = JsonObjectKeys(joSchema);
    int i; for (i = 0; i < JsonGetLength(jaKeys); i++)
    {
        string sKey = JsonGetString(JsonArrayGet(jaKeys, i));
        if (sKey == "enum" || sKey == "const")
            continue;

        json jValue = JsonObjectGet(joSchema, sKey);
        int nType = JsonGetType(jValue);

        if (nType == JSON_TYPE_OBJECT)
        {
            joMap = schema_util_MapIDs(jValue, sBaseURI, joMap);
        }
        else if (nType == JSON_TYPE_ARRAY)
        {
            int j; for (j = 0; j < JsonGetLength(jValue); j++)
            {
                joMap = schema_util_MapIDs(JsonArrayGet(jValue, j), sBaseURI, joMap);
            }
        }
    }

    return joMap;
}

/// @brief Annotates the output with a metadata keyword.
/// @param sKey The metadata keyword.
/// @param jValue The value for the metadata keyword.
/// @returns An output object containing the annotation.
json schema_validate_Metadata(string sKey, json jValue)
{
    return schema_output_SetAnnotation(schema_output_GetOutputUnit(), sKey, jValue);
}

json schema_core_Validate(json jInstance, json joSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);

    schema_debug_Argument(__FUNCTION__, "instance", jInstance);
    schema_debug_Argument(__FUNCTION__, "schema", joSchema);

    json joOutputUnit = schema_output_GetOutputUnit();

    if (JsonGetType(joSchema) == JSON_TYPE_NULL)
    {
        schema_output_SetError(joOutputUnit, "Schema resolution failed (JsonNull)", __FUNCTION__);
        schema_debug_ExitFunction(__FUNCTION__);
        joOutputUnit = schema_output_SetValid(joOutputUnit, FALSE);
        schema_output_SaveValidationResult(joOutputUnit);
        return joOutputUnit;
    }

    int bDebugSkip = FALSE;

    json jResult = JsonNull();
    
    if (joSchema == JSON_TRUE || joSchema == JsonObject())
    {
        schema_debug_ExitFunction(__FUNCTION__);
        joOutputUnit = schema_output_SetValid(joOutputUnit, TRUE);
        schema_output_SaveValidationResult(joOutputUnit);
        return joOutputUnit;
    }
    if (joSchema == JSON_FALSE)
    {
        schema_debug_ExitFunction(__FUNCTION__);
        joOutputUnit = schema_output_SetValid(joOutputUnit, FALSE);
        schema_output_SaveValidationResult(joOutputUnit);
        return joOutputUnit;
    }

    json jaSchemaKeys = JsonObjectKeys(joSchema);
    
    /// @todo
    ///     [ ] move this to a PrepareEnvironment function

    /// @todo
    ///     only load the keyword map if this is the base-level of a schema validation, not
    ///     every time we come through here since this is super-recursive.
    /// @brief Keep track of the current schema.  $schema should only be present in the root note
    ///     of any schema, so if it's present, assume that we're starting a new validation.
    int nLexicalScopes = 0;
    string sSchema = JsonGetString(JsonObjectGet(joSchema, "$schema"));
    if (sSchema != "")
    {
        schema_scope_PushSchema(sSchema);
        schema_scope_SetBaseSchema(joSchema);
        nLexicalScopes++;
        SetLocalJson(GetModule(), "SCHEMA_KEYWORD_MAP", schema_keyword_LoadTypeMap(sSchema));

        /// @note Map all IDs in the document for reference resolution.  This allows us to
        ///     resolve internal references that haven't been saved to the database yet.
        string sRootID = JsonGetString(JsonObjectGet(joSchema, "$id"));
        if (sRootID == "")
            sRootID = JsonGetString(JsonObjectGet(joSchema, "id"));
        
        json joIDMap = schema_util_MapIDs(joSchema, sRootID, JsonObject());
        SetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP", joIDMap);
    }

    /// @todo
    ///     [ ] Handle nDraft = 0 ?
    ///     [ ] can this be done without nDraft at all?
    ///         probably, but we'd need to do the keyword validation/matching check within the
    ///         group functions, which is likelyl doable to do away with the everything that
    ///         has to do with drafts, which is prefereable!
    int nDraft = JsonGetInt(schema_scope_GetSchema());
    if (nDraft == 0)
        nDraft = SCHEMA_DRAFT_LATEST;

    /// @note Handle $id (or id) to establish new Base URI context.
    string sID = JsonGetString(JsonObjectGet(joSchema, "$id"));
    if (sID == "" && nDraft < SCHEMA_DRAFT_2019_09)
        sID = JsonGetString(JsonObjectGet(joSchema, "id"));

    if (sID != "")
    {
        // Resolve ID against current base schema
        json joBase = schema_scope_GetBaseSchema();
        string sBaseURI = JsonGetString(JsonObjectGet(joBase, "$id"));
        if (sBaseURI == "" && nDraft < SCHEMA_DRAFT_2019_09)
            sBaseURI = JsonGetString(JsonObjectGet(joBase, "id"));
        
        // If we have a base URI, resolve the new ID against it
        if (sBaseURI != "")
        {
            sID = schema_reference_ResolveURI(sBaseURI, sID);
            
            /// @note Update the schema object with the absolute ID for the scope.
            ///     We create a shallow copy with the updated ID to push to the stack.
            ///     This ensures children resolve against the absolute URI.
            json joNewScope = JsonObjectSet(joSchema, "$id", JsonString(sID));
            schema_scope_PushLexical(joNewScope);
            nLexicalScopes++;
        }
        else
        {
            /// @note If no base URI (e.g. root with relative ID?), just push as is.
            ///     But usually root has absolute ID or we treat it as such.
            schema_scope_PushLexical(joSchema);
            nLexicalScopes++;
        }
    }

    int bDynamicAnchor = FALSE;
    if (JsonFind(jaSchemaKeys, JsonString("$dynamicAnchor")) != JsonNull() ||
        JsonFind(jaSchemaKeys, JsonString("$recursiveAnchor")) != JsonNull())
    {
        schema_scope_PushDynamic(joSchema);
        bDynamicAnchor = TRUE;
    }

    /// @todo
    ///     [ ] These resolution functions can and will return JsonNull().  Check for that before
    ///         invoking another validation process.
    
    /// @brief Resolve references, dynamic references and recursive references.  Dynamic and recursive
    ///     references take advantage of dynamic scope to find the appropriate anchor/subschema.  If
    ///     dynamic or recursive references cannot be resolved for any reason, they revert to resolving
    ///     exactly like a normal $ref.
    
    json jRef = JsonObjectGet(joSchema, "$ref");
    if (JsonGetType(jRef) != JSON_TYPE_NULL)
    {
        schema_scope_PushSchemaPath("$ref");
        jResult = schema_core_Validate(jInstance, schema_reference_ResolveRef(joSchema, jRef));
        schema_scope_PopSchemaPath();
    }
    else
    {
        jRef = JsonObjectGet(joSchema, "$dynamicRef");
        if (JsonGetType(jRef) != JSON_TYPE_NULL)
        {
            schema_scope_PushSchemaPath("$dynamicRef");
            int bRevertToRef = nDraft >= SCHEMA_DRAFT_2019_09 && nDraft <= SCHEMA_DRAFT_2020_12;
            jResult = schema_core_Validate(jInstance, schema_reference_ResolveDynamicRef(joSchema, jRef, bRevertToRef));
            schema_scope_PopSchemaPath();
        }
        else
        {
            jRef = JsonObjectGet(joSchema, "$recursiveRef");
            if (JsonGetType(jRef) != JSON_TYPE_NULL)
            {
                schema_scope_PushSchemaPath("$recursiveRef");
                jResult = schema_core_Validate(jInstance, schema_reference_ResolveRecursiveRef(joSchema));
                schema_scope_PopSchemaPath();
            }
        }
    }

    /// @brief If a reference was found, incorporate the results into the output unit.  For schema drafts-4,
    /// -6 and -7, the foundational documents forbid processing adjacent keywords.
    if (JsonGetType(jRef) != JSON_TYPE_NULL)
    {
        if (JsonGetType(jResult) != JSON_TYPE_NULL)
        {
            if (schema_output_GetValid(jResult))
                joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, jResult);
            else
                joOutputUnit = schema_output_InsertError(joOutputUnit, jResult);
        }
        else
        {
            /// @todo
            ///     [ ] What do we do with a JsonNull() return from $ref validation?
        }

        if (nDraft >= SCHEMA_DRAFT_4 && nDraft <= SCHEMA_DRAFT_7)
        {
            if (bDynamicAnchor)
                schema_scope_PopDynamic();
            
            while (nLexicalScopes > 0)
            {
                schema_scope_PopLexical();
                nLexicalScopes--;
            }

            schema_debug_ExitFunction(__FUNCTION__);
            return joOutputUnit;
        }
    }

    int HANDLED_CONDITIONAL = 0x01;
    int HANDLED_CONTAINS = 0x02;
    int HANDLED_OBJECT = 0x04;
    int HANDLED_ITEMS = 0x08;
    int nHandledFlags;

    int i; for (; i < JsonGetLength(jaSchemaKeys); i++)
    {
        jResult = JsonNull();
        string sKey = JsonGetString(JsonArrayGet(jaSchemaKeys, i));

        if (sKey == "$ref" || sKey == "$dynamicRef" || sKey == "$recursiveRef" || 
            sKey == "$schema" || sKey == "$id" || sKey == "id" || 
            sKey == "$defs" || sKey == "definitions" || 
            sKey == "$anchor" || sKey == "$dynamicAnchor" || sKey == "$recursiveAnchor")
            continue;

        /// @todo let's modify this approach once this is implemented:
        ///     for the groups, we'll do the keyword checks individually to the map, thus avoiding the
        ///     need for nDraft (?).
        ///     after the groups, we'll run a `is skey in map` check for all the remaining keys
        
        //// Check if the keyword applies to the current instance type
        //if (!schema_validate_AssertInstanceType(sKey, jInstance))
        //    continue;

        /// @note Our grouped keyword evaluations contain draft guards because they could potentially
        ///     end-around or keyword/draft matching system given the way they are extracted from
        ///     the json schema.  If the user provides a schema that contains a keyword that is invalid
        ///     for the draft (such as additionalItems in draft 2020_12), including the keyword items
        ///     (which is valid in 2020_12) will automatically include the additionalItems keyword, even
        ///     though it's invalid.  The single keyword validation process checks for those, so no
        ///     issue in those, only these groups need guarding.

        if (sKey == "if" || sKey == "then" || sKey == "else")
        {
            if (nDraft >= SCHEMA_DRAFT_7)            
            {
                if (!(nHandledFlags & HANDLED_CONDITIONAL))
                {
                    jResult = schema_validate_If(jInstance,
                        JsonObjectGet(joSchema, "if"),
                        JsonObjectGet(joSchema, "then"),
                        JsonObjectGet(joSchema, "else"),
                        nDraft >= SCHEMA_DRAFT_2019_09
                    );
                    nHandledFlags |= HANDLED_CONDITIONAL;
                }
                else
                    continue;
            }
        }
        else if (sKey == "contains" || sKey == "minContains" || sKey == "maxContains")
        {
            if (!(nHandledFlags & HANDLED_CONTAINS))
            {
                jResult = schema_validate_Contains(jInstance,
                    (nDraft >= SCHEMA_DRAFT_6 ? JsonObjectGet(joSchema, "contains") : JsonNull()),
                    (nDraft >= SCHEMA_DRAFT_2019_09 ? JsonObjectGet(joSchema, "minContains") : JsonNull()),
                    (nDraft >= SCHEMA_DRAFT_2019_09 ? JsonObjectGet(joSchema, "maxContains") : JsonNull()),
                    nDraft >= SCHEMA_DRAFT_2019_09
                );
                nHandledFlags |= HANDLED_CONTAINS;
            }
            else
                continue;
        }
        else if (sKey == "properties" || sKey == "patternProperties" ||
            sKey == "additionalProperties" || sKey == "dependencies" ||
            sKey == "dependentSchemas")
        {
            if (!(nHandledFlags & HANDLED_OBJECT))
            {
                jResult = schema_validate_Object(jInstance,
                    JsonObjectGet(joSchema, "properties"),
                    JsonObjectGet(joSchema, "patternProperties"),
                    JsonObjectGet(joSchema, "additionalProperties"),
                    (nDraft < SCHEMA_DRAFT_2019_09 ? JsonObjectGet(joSchema, "dependencies") : JsonNull()),
                    (nDraft >= SCHEMA_DRAFT_2019_09 ? JsonObjectGet(joSchema, "dependentSchemas") : JsonNull()),
                    nDraft >= SCHEMA_DRAFT_2019_09
                );
                nHandledFlags |= HANDLED_OBJECT;
            }
            else
                continue;
        }
        else if (sKey == "prefixItems" || sKey == "items" || sKey == "additionalItems")
        {
            if (!(nHandledFlags & HANDLED_ITEMS))
            {
                jResult = schema_validate_Items(jInstance,
                    (nDraft >= SCHEMA_DRAFT_2020_12 ? JsonObjectGet(joSchema, "prefixItems") : JsonNull()),
                    JsonObjectGet(joSchema, "items"),
                    (nDraft < SCHEMA_DRAFT_2020_12 ? JsonObjectGet(joSchema, "additionalItems") : JsonNull()),
                    nDraft >= SCHEMA_DRAFT_2019_09
                );
                nHandledFlags |= HANDLED_ITEMS;
            }
            else
                continue;
        }

        else if (sKey == "title" || sKey == "description" || sKey == "default" ||
            sKey == "deprecated" || sKey == "readOnly" || sKey == "writeOnly" ||
            sKey == "examples")
        {
            jResult = schema_validate_Metadata(sKey, JsonObjectGet(joSchema, sKey));
        }
        else if (sKey == "unevaluatedProperties" || sKey == "unevaluatedItems")
            continue;

        json jKeySchema = JsonObjectGet(joSchema, sKey);
        int nKeySchemaType = JsonGetType(jKeySchema);

        int nSchemaType = JsonGetType(joSchema);

        schema_scope_PushSchemaPath(sKey);

        if (sKey == "minimum")
            jResult = schema_validate_Assertion(sKey, jInstance, ">=", jKeySchema);
        else if (sKey == "maximum")
            jResult = schema_validate_Assertion(sKey, jInstance, "<=", jKeySchema);
        else if (sKey == "exclusiveMinimum" || sKey == "exclusiveMaximum")
        {
            string sOperator = sKey == "exclusiveMinimum" ? ">" : "<";

            if (nKeySchemaType == JSON_TYPE_INTEGER || nKeySchemaType == JSON_TYPE_FLOAT)
                jResult = schema_validate_Assertion(sKey, jInstance, sOperator, jKeySchema);
            else if (nKeySchemaType == JSON_TYPE_BOOL && jKeySchema == JSON_TRUE)
            {
                string sKeyword = sKey == "exclusiveMinimum" ? "minimum" : "maximum";

                json jKeyword = JsonObjectGet(joSchema, sKeyword);
                int nKeywordType = JsonGetType(jKeyword);
                if (nKeywordType == JSON_TYPE_INTEGER || nKeywordType == JSON_TYPE_FLOAT)
                    jResult = schema_validate_Assertion(sKey, jInstance, sOperator, jKeyword);
                else
                    continue;
            }
            else
                continue;
        }
        else if (sKey == "minItems")
            jResult = schema_validate_Assertion(sKey, jInstance, ">=", jKeySchema);
        else if (sKey == "maxItems")
            jResult = schema_validate_Assertion(sKey, jInstance, "<=", jKeySchema);
        else if (sKey == "minLength")
            jResult = schema_validate_Assertion(sKey, jInstance, ">=", jKeySchema);
        else if (sKey == "maxLength")
            jResult = schema_validate_Assertion(sKey, jInstance, "<=", jKeySchema);
        else if (sKey == "minProperties")
            jResult = schema_validate_Assertion(sKey, jInstance, ">=", jKeySchema);
        else if (sKey == "maxProperties")
            jResult = schema_validate_Assertion(sKey, jInstance, "<=", jKeySchema);
        else if (sKey == "multipleOf")
            jResult = schema_validate_Assertion(sKey, jInstance, "%", jKeySchema);
        else if (sKey == "type")
            jResult = schema_validate_Type(jInstance, jKeySchema);
        else if (sKey == "enum")
            jResult = schema_validate_Enum(jInstance, jKeySchema, sKey);
        else if (sKey == "const")
            jResult = schema_validate_Enum(jInstance, jKeySchema, sKey);
        else if (sKey == "allOf")
            jResult = schema_validate_AllOf(jInstance, jKeySchema, nDraft >= SCHEMA_DRAFT_2019_09);
        else if (sKey == "anyOf")
            jResult = schema_validate_AnyOf(jInstance, jKeySchema, nDraft >= SCHEMA_DRAFT_2019_09);
        else if (sKey == "oneOf")
            jResult = schema_validate_OneOf(jInstance, jKeySchema, nDraft >= SCHEMA_DRAFT_2019_09);
        else if (sKey == "not")
            jResult = schema_validate_Not(jInstance, jKeySchema);
        else if (sKey == "required")
            jResult = schema_validate_Required(jInstance, jKeySchema);
        else if (sKey == "dependentRequired")
            jResult = schema_validate_DependentRequired(jInstance, jKeySchema);
        else if (sKey == "propertyNames")
            jResult = schema_validate_PropertyNames(jInstance, jKeySchema);
        else if (sKey == "pattern")
            jResult = schema_validate_Pattern(jInstance, jKeySchema);
        else if (sKey == "uniqueItems")
            jResult = schema_validate_UniqueItems(jInstance, jKeySchema);
        else if (sKey == "format")
            jResult = schema_validate_Format(jInstance, jKeySchema);

        schema_scope_PopSchemaPath();

        int nResultType = JsonGetType(jResult);
        if (nResultType == JSON_TYPE_ARRAY)
        {
            /// @note Array results are returned from compound validation functions.  For classification
            ///     purposes, the entire result set is either an annotation or an error, regardless of
            ///     the mix.  A single error results in the entire set being classified as an error array.
            int nResultLength = JsonGetLength(jResult);
            int i; for (; i < nResultLength; i++)
            {
                if (!schema_output_GetValid(JsonArrayGet(jResult, i)))
                    break;
            }

            //schema_debug_Json("Post Array Loop :: jResult", jResult);
            //schema_debug_Value("Post Array Loop :: nResultLength", IntToString(nResultLength));
            //schema_debug_Value("Post Array Loop :: i", IntToString(i));

            int j; for (; j < nResultLength; j++)
            {
                joOutputUnit = i == nResultLength ? 
                    schema_output_InsertAnnotation(joOutputUnit, JsonArrayGet(jResult, j)) :
                    schema_output_InsertError(joOutputUnit, JsonArrayGet(jResult, j));
            }
            
            if (SOURCE)
            {
                string sSource = __FUNCTION__ + " (array)";
                joOutputUnit = JsonObjectSet(joOutputUnit, "source", JsonString(sSource));
            }   

            /// @note Since schema_output_Insert* is not called here, the result must be
            ///     manually saved to ensure its availability to the calling functions.
            schema_output_SaveValidationResult(joOutputUnit);
        }
        else if (nResultType == JSON_TYPE_OBJECT)
        {
            /// @note Object results are returned from singular validation functions.  Results are
            ///     returned with the appropriate classification, so the only processing required
            ///     is to insert them into the appropriate array in the parent output unit.
            string sSource = __FUNCTION__ + " (object)";

            if (schema_output_GetValid(jResult))
                joOutputUnit = schema_output_InsertAnnotation(joOutputUnit, jResult, sSource);
            else
                joOutputUnit = schema_output_InsertError(joOutputUnit, jResult, sSource);
        }
        else
        {
            jResult = JsonObjectSet(JsonObject(), "valid", JsonBool(TRUE));
            /// @todo
            ///     [ ] When integrating joResult, we'll make JsonNull() mean that the keyword is not handled and/or supported?
        }
    }

    /// @todo
    ///     [ ] process unevaluatedItems and unevaluatedProperties here
    ///         We'll use the jInstance to grab the appropriate object keys, if they exist
    ///         the fucntion needs full access to jResult to pull the appropraite evaluated
    ///         keys from the result set.
    ///     [ ] This should return a set ready to go straight into the output.
    ///     [ ] check keyword map
    joOutputUnit = schema_validate_Unevaluated(jInstance, joSchema, joOutputUnit);

    if (bDynamicAnchor)
        schema_scope_PopDynamic();

    while (nLexicalScopes > 0)
    {
        schema_scope_PopLexical();
        nLexicalScopes--;
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// -----------------------------------------------------------------------------------------------
///                                     PUBLIC API
/// -----------------------------------------------------------------------------------------------

/// @private Checks if a schema is trusted based on its ID.
/// @param joSchema The schema to check.
/// @returns TRUE if the schema is trusted, FALSE otherwise.
int schema_core_IsSchemaTrusted(json joSchema)
{
    string sID = JsonGetString(JsonObjectGet(joSchema, "$id"));
    if (sID == "")
        sID = JsonGetString(JsonObjectGet(joSchema, "id"));

    if (sID == "")
        return FALSE;

    if (FindSubString(sID, "http://json-schema.org") != -1 || 
        FindSubString(sID, "https://json-schema.org") != -1)
        return TRUE;

    return FALSE;
}

/// @brief Loads a schema into the system.
/// @param joSchema The schema object to load.
/// @param sDefaultDraft The default draft to use if $schema is missing.
/// @param joOverlay An optional overlay object to ingest (e.g. for standard drafts).
/// @returns A JSON object containing the validation results of the schema load operation.
/// @note This function saves the schema to the database and ingests any keyword type definitions
///     found in the schema (if it is a metaschema) or the overlay.
json schema_Load(json joSchema, string sDefaultDraft = "", json joOverlay = JSON_NULL)
{
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
        return schema_output_SetValid(schema_output_GetMinimalObject(), FALSE);

    // 1. Check if it's a known metaschema (trusted)
    int bIsMetaschema = schema_core_IsSchemaTrusted(joSchema);

    // 2. If not a metaschema, validate it against its $schema
    if (!bIsMetaschema)
    {
        string sMetaSchemaID = JsonGetString(JsonObjectGet(joSchema, "$schema"));
        if (sMetaSchemaID == "")
            sMetaSchemaID = (sDefaultDraft != "") ? sDefaultDraft : SCHEMA_DEFAULT_DRAFT;

        // Ensure the metaschema is loaded
        json joMetaSchema = schema_reference_GetSchema(sMetaSchemaID);
        if (JsonGetType(joMetaSchema) == JSON_TYPE_NULL)
        {
            json joError = schema_output_GetMinimalObject();
            joError = schema_output_SetValid(joError, FALSE);
            return schema_output_SetError(joError, "Metaschema not found: " + sMetaSchemaID);
        }

        // Validate the schema against its metaschema
        json joResult = schema_Validate(joSchema, sMetaSchemaID);
        if (!schema_output_GetValid(joResult))
        {
            return joResult;
        }
    }

    schema_reference_SaveSchema(joSchema);
    return schema_output_SetValid(schema_output_GetMinimalObject(), TRUE);
}

/// @brief Validates an instance against a loaded schema.
/// @param jInstance The JSON instance to validate.
/// @param sSchemaID The ID of the schema to validate against.
/// @returns A JSON object containing the validation results (verbose format).
json schema_Validate(json jInstance, string sSchemaID)
{
    // 1. Prepare Environment
    schema_core_CreateTables();
    schema_scope_Destroy();

    // 2. Get Schema
    json joSchema = schema_reference_GetSchema(sSchemaID);
    if (JsonGetType(joSchema) == JSON_TYPE_NULL)
    {
        json joError = schema_output_GetMinimalObject();
        joError = schema_output_SetValid(joError, FALSE);
        return schema_output_SetError(joError, "Schema not found: " + sSchemaID);
    }

    // 3. Validate
    json joResult = schema_core_Validate(jInstance, joSchema);

    // 4. Return Result
    return joResult;
}

/// @brief Validates an instance against a user-provided schema object.
/// @param jInstance The JSON instance to validate.
/// @param joSchema The schema object to validate against.
/// @param sDefaultDraft The default draft to use if the schema is missing $schema.
/// @returns A JSON object containing the validation results.
json schema_ValidateObject(json jInstance, json joSchema, string sDefaultDraft = "")
{
    // 1. Load (and validate) the schema
    json joLoadResult = schema_Load(joSchema, sDefaultDraft);
    if (!schema_output_GetValid(joLoadResult))
        return joLoadResult;

    // 2. Prepare Environment
    schema_core_CreateTables();
    schema_scope_Destroy();

    // 3. Validate Instance against Schema Object directly
    return schema_core_Validate(jInstance, joSchema);
}

int ValidateSchema(json joSchema, int nDraft = 0);
int ValidateInstance(json jInstance, string sID = "");

int ValidateInstanceAdHoc(json jInstance, json joSchema)
{
    schema_scope_Destroy();
    json joResult = schema_core_Validate(jInstance, joSchema);
    return schema_output_GetValid(joResult);
}
