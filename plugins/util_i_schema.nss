
#include "util_i_debug"
#include "util_i_strings"
#include "util_i_unittest"
#include "util_c_schema"

json joScopes = JsonParse(r"{
    ""SCHEMA_SCOPE_CONTEXT"": [],
    ""SCHEMA_SCOPE_DYNAMIC"": [],
    ""SCHEMA_SCOPE_INSTANCEPATH"": [],
    ""SCHEMA_SCOPE_LEXICAL"": [],
    ""SCHEMA_SCOPE_SCHEMAPATH"": [],
    ""SCHEMA_SCOPE_KEYMAP"": [],
    ""SCHEMA_SCOPE_ABSOLUTE_URI"": []
}");

json jaContextKeys = JsonParse(r"[
    ""SCHEMA_CONTEXT_EVALUATED_PROPERTIES"",
    ""SCHEMA_CONTEXT_EVALUATED_ITEMS""
]");

int ValidateInstanceAdHoc(json jInstance, json joSchema);
json schema_output_GetValidationResult();
void schema_reference_SaveSchema(json joSchema);

json schema_core_Validate(json jInstance, json joSchema);
json schema_reference_GetSchema(string sSchemaID);
json schema_keyword_GetMap(string sSchemaID, json joSchema = JSON_NULL, int bForce = FALSE);

/// -----------------------------------------------------------------------------------------------
///                                     DEBUGGING FACILITATION
/// -----------------------------------------------------------------------------------------------

/// @note Testing and Debugging functions facilitate ensuring the system is running as intended.
///     Test functions are designed to receive an array of tests (the "test suite") from a source
///     such as json-schema.org's test suite.  This can be added via scripts or from the specified
///     text file for quick iteration.  Test Groups (each entry in a test suite array) are run
///     via DelayCommand() to greatly reduce the chances of encountering a TMI error.

/// @warning Running schema validation with debugging messaging turned on adds a massive amount
///     of overhead and excessive instruction count.  If debugging messaging is required, limit
///     the scope of the tests being run to reduce the chances of encountering a TMI error.
///     If utilizing NWNX:EE, increase the instruction count before executing tests in debugging mode.

/// @brief Verbose schema output generally holds enough information to determine where
///     an error occurs in a schema or instance.  Setting this value to TRUE will
///     add the validation source (usually the function name) to each output node.
/// @note Sources are useful for debugging validation errors, but essentially useless during normal
///     usages, so this value should normally be set to FALSE.
const int SCHEMA_OUTPUT_INCLUDE_SOURCE = FALSE;

/// @brief Verbose output nodes can be nested quite deeply and it can be difficult to trace where some
///     nodes originate.  Set this value to TRUE to invlude a UUID for each node to make tracing
///     nodes origins easier in some cases.
const int SCHEMA_OUTPUT_INCLUDE_UUID = FALSE;

void schema_test_RunTestGroup(json joGroup)
{
    json joSchema = JsonObjectGet(joGroup, "schema");
    json jaTests = JsonObjectGet(joGroup, "tests");
    DescribeTestGroup(JsonGetString(JsonObjectGet(joGroup, "description")));
    
    int j; for (; j < JsonGetLength(jaTests); j++)
    {
        json joTest = JsonArrayGet(jaTests, j);
        json jsDescription = JsonObjectGet(joTest, "description");
        json jInstance = JsonObjectGet(joTest, "data");
        json jbValid = JsonObjectGet(joTest, "valid");
        
        int bValid = ValidateInstanceAdHoc(jInstance, joSchema);

        if (!Assert(JsonGetString(jsDescription), bValid == JsonGetInt(jbValid)))
        {
            DescribeTestParameters(JsonDump(joTest), JsonDump(jbValid), JsonDump(JsonBool(bValid)));
            Debug(HexColorString(JsonDump(schema_output_GetValidationResult(), 4), COLOR_BLUE_LIGHT));
        }
    } Outdent();
}

void schema_test_RunTestSuite(json jaSuite)
{
    int i; for (; i < JsonGetLength(jaSuite); i++)
    {
        json joGroup = JsonArrayGet(jaSuite, i);
        DelayCommand(0.0, schema_test_RunTestGroup(joGroup));
    }
}

void schema_test_RunTestSuiteFromFile()
{
    schema_test_RunTestSuite(JsonParse(ResManGetFileContents("test", RESTYPE_TXT)));
}

int schema_debug_IsDebugging()
{
    return GetLocalInt(GetModule(), "SCHEMA_VALIDATION_DEBUGGING");
}

void schema_debug_Indent()
{
    int n = GetLocalInt(GetModule(), "schema_debug_indent");
    SetLocalInt(GetModule(), "schema_debug_indent", ++n);
}

void schema_debug_Outdent()
{
    int n = GetLocalInt(GetModule(), "schema_debug_indent");
    SetLocalInt(GetModule(), "schema_debug_indent", --n);
}

string schema_debug_GetIndent()
{
    int nSpaces = 4;
    int n = GetLocalInt(GetModule(), "schema_debug_indent");

    string s;
    int i; for (; i <= n * nSpaces; i++)
        s+= " ";

    return s;
}

void schema_debug_Argument(string sFunction, string sArg, json jValue)
{
    if (!schema_debug_IsDebugging()) return;

    Debug(schema_debug_GetIndent() + HexColorString(sArg + ": ", COLOR_BLUE_STEEL) + HexColorString(JsonDump(jValue), COLOR_BLUE_LIGHT));
}

void schema_debug_Message(string sMessage)
{
    if (!schema_debug_IsDebugging()) return;

    Debug(schema_debug_GetIndent() + sMessage);
}

void schema_debug_Value(string sTitle, string sValue)
{
    if (!schema_debug_IsDebugging()) return;
    Debug(schema_debug_GetIndent() + sTitle + " = " + HexColorString(sValue, COLOR_MAGENTA));
}

void schema_debug_Json(string sTitle, json jValue)
{
    if (!schema_debug_IsDebugging()) return;
    Debug(schema_debug_GetIndent() + sTitle);
    Debug(HexColorString(JsonDump(jValue, 4), COLOR_SALMON));
}

void schema_debug_Output(string sTitle, json joOutputUnit, int bID = FALSE)
{
    if (!schema_debug_IsDebugging()) return;

    Debug(schema_debug_GetIndent() + "Output validity @ " + sTitle + " = " +
        HexColorString(JsonObjectGet(joOutputUnit, "valid") == JSON_TRUE ? "TRUE" : "FALSE", COLOR_ORANGE) +
        (bID ? " for " + HexColorString(JsonDump(JsonObjectGet(joOutputUnit, "uuid")), COLOR_CYAN_DARK) : ""));
}

void schema_debug_EnterFunction(string sFunction)
{
    if (!schema_debug_IsDebugging()) return;

    int n = GetLocalInt(GetModule(), sFunction);
    SetLocalInt(GetModule(), sFunction, ++n);
    Debug(schema_debug_GetIndent() + HexColorString("-> " + sFunction, COLOR_GREEN_LIGHT) + " " + HexColorString("(" + IntToString(n) + ")", COLOR_BLUE_LIGHT));

    schema_debug_Indent();
}

void schema_debug_ExitFunction(string sFunction, string sMessage = "")
{
    if (!schema_debug_IsDebugging()) return;

    if (sMessage != "")
        schema_debug_Message(sMessage);

    schema_debug_Outdent();

    int n = GetLocalInt(GetModule(), sFunction);
    Debug(schema_debug_GetIndent() + HexColorString("<- " + sFunction, COLOR_RED_LIGHT) + " " + HexColorString("(" + IntToString(n) + ")", COLOR_BLUE_LIGHT));
    SetLocalInt(GetModule(), sFunction, --n);
}

/// -----------------------------------------------------------------------------------------------
///                                         QUERY MANAGEMENT
/// -----------------------------------------------------------------------------------------------

/// @private Prepare a query for any schema-related database or for module use.
/// @param s The query string to prepare.
/// @param bForceModule If TRUE, the query is prepared for the module database.
sqlquery schema_core_PrepareQuery(string s, int bForceModule = FALSE)
{
    json joTables = JsonParse(r"
        {
            ""schema_schema"": """ + schema_GetSchemaTableName() + r""",
            ""schema_output"": """ + schema_GetOutputTableName() + r"""
        }
    ");
    s = SubstituteStrings(s, joTables);

    if (bForceModule)
        return SqlPrepareQueryObject(GetModule(), s);
    else
        return SqlPrepareQueryCampaign(schema_GetDatabaseName(), s);
}

void schema_core_ExecuteQuery(string s, int bForceModule = FALSE)
{
    SqlStep(schema_core_PrepareQuery(s, bForceModule));
}

sqlquery schema_core_PrepareModuleQuery(string s)
{
    return schema_core_PrepareQuery(s, TRUE);
}

sqlquery schema_core_PrepareCampaignQuery(string s)
{
    return schema_core_PrepareQuery(s, FALSE);
}

void schema_core_ExecuteModuleQuery(string s)
{
    schema_core_ExecuteQuery(s, TRUE);
}

void schema_core_ExecuteCampaignQuery(string s)
{
    schema_core_ExecuteQuery(s, FALSE);
}

void schema_core_BeginTransaction(int bForceModule = FALSE)
{
    schema_core_ExecuteQuery("BEGIN TRANSACTION;", bForceModule);
}

void schema_core_CommitTransaction(int bForceModule = FALSE)
{
    schema_core_ExecuteQuery("COMMIT TRANSACTION;", bForceModule);
}

void schema_core_CreateTables(int bForce = FALSE)
{
    /// @note THis function is called automatically to ensure the database tables are initialized
    ///     without any action required by the user, thus ensuring the database tables are
    ///     always available to the system.  To prevent execution of a large number of useless,
    ///     repetitive queries, use a two step process to determine if the tables are loaded:
    ///     1) Check if the initialization variable has been set on the module (shortcut), or
    ///     2) Check if the tables already exist in the database (less of a shortcut)

    if (!bForce)
    {
        if (GetLocalInt(GetModule(), "SCHEMA_DATABASE_INITIALIZED"))
            return;
        else
        {
            string s = r"
                SELECT count(*)
                FROM sqlite_master 
                WHERE type = 'table' 
                    AND name IN ('$schema_schema', '$schema_output');
            ";
            sqlquery q = schema_core_PrepareCampaignQuery(s);
            if (SqlStep(q) && SqlGetInt(q, 0) == 2)
            {
                SetLocalInt(GetModule(), "SCHEMA_DATABASE_INITIALIZED", TRUE);
                return;
            }
        }
    }

    schema_core_BeginTransaction(); 

    /// @note This table holds all validated schema, including meta schema provided by json-schema.org
    ///     All user-provided schema will also be saved to this table for retrieval or later use.
    ///     If the UNIQUE key is violated, the record will be removed and replaced (not updated) by
    ///     the incoming schema.
    string s = r"
        CREATE TABLE IF NOT EXISTS $schema_schema (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            schema TEXT NOT NULL,
            keymap TEXT,
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
    schema_core_ExecuteCampaignQuery(s);

    s = r"
        CREATE INDEX IF NOT EXISTS schema_index ON $schema_schema (schema_id);
    ";
    schema_core_ExecuteCampaignQuery(s);

    s = r"
        CREATE TABLE IF NOT EXISTS $schema_output (
            verbosity TEXT NOT NULL,
            schema TEXT NOT NULL,
            output TEXT NOT NULL DEFAULT '{}',
            schema_id TEXT GENERATED ALWAYS AS (json_extract(schema, '$.$id')) STORED,
            PRIMARY KEY (verbosity, schema) ON CONFLICT REPLACE
        );
    ";
    schema_core_ExecuteCampaignQuery(s);

    json jaTrustedSchema = schema_core_GetTrustedSchema(TRUE);
    int i; for (i = 0; i < JsonGetLength(jaTrustedSchema); i++)
    {
        json joSchema = JsonArrayGet(jaTrustedSchema, i);
        json jID = JsonObjectGet(joSchema, "$id");
        if (JsonGetType(jID) == JSON_TYPE_NULL)
            jID = JsonObjectGet(joSchema, "id");

        if (JsonGetType(jID) != JSON_TYPE_NULL)
            schema_reference_SaveSchema(joSchema);
    }

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
///     new members are initialized to the default values found in joScopes.
void schema_scope_ResizeArrays()
{
    schema_debug_EnterFunction(__FUNCTION__);

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

    schema_debug_ExitFunction(__FUNCTION__);
}

/// @private Retrieve the current scope depth.
/// @returns The current scope depth, base 1.
/// @note This will rarely be greater than one, however, this value will increment
///     if nested validations are initiated, such as referencing a non-trusted schema
///     that has not been previously validated.
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
        JsonArraySetInplace(jaScopes, nDepth, JsonArrayInsert(jaScope, jItem));
    else if (nIndex >= 0)
        JsonArraySetInplace(jaScopes, nDepth, JsonArraySet(jaScope, nIndex, jItem));
}

/// @private Push a new item into the specified scope array at the current depth.
/// @param sScope Scope type SCHEMA_SCOPE_*; must be a simple array.
/// @param jItem The json object to push into the array.
void schema_scope_PushItem(string sScope, json jItem)
{
    json jaScope = GetLocalJson(GetModule(), sScope);
    if (JsonGetType(jaScope) != JSON_TYPE_ARRAY)
        return;

    JsonArraySetInplace(jaScope, schema_scope_GetDepth(), jItem);
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
            JsonArrayInsertInplace(jaContext, JsonObjectGet(joScopes, sScopeKey));

        schema_scope_PushArrayItem(sScopeKey, jaContext);
    }

    return JsonArrayGet(jaContext, JsonGetInt(jIndex));
}

/// @private Deconstruct a pointer string into an array of pointer segments.
/// @param sPointer The pointer string to deconstruct.
/// @returns A json array containing the path segments, or an empty json array if the path is empty.
json schema_scope_DeconstructPointer(string sPointer)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sPointer", JsonString(sPointer));

    // Remove leading # if present
    if (GetStringLeft(sPointer, 1) == "#")
        sPointer = GetStringRight(sPointer, GetStringLength(sPointer) - 1);

    if (sPointer == "")
    {
        schema_debug_ExitFunction(__FUNCTION__, "sPointer is an empty string");
        return JsonArray();
    }

    // If it starts with /, remove it to simplify splitting, but keep track that we did
    if (GetStringLeft(sPointer, 1) == "/")
        sPointer = GetStringRight(sPointer, GetStringLength(sPointer) - 1);
    else
    {
        schema_debug_ExitFunction(__FUNCTION__, "sPointer is not a valid pointer");
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
    
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindString(q, ":str", sPointer);

    json jaPointer = SqlStep(q) ? SqlGetJson(q, 0) : JsonArray();
    schema_debug_ExitFunction(__FUNCTION__, JsonDump(jaPointer));
    return jaPointer;
}

/// @private Escape a string for use in a JSON pointer (~ -> ~0, / -> ~1)
string schema_reference_EscapePointer(string sToken)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sToken", JsonString(sToken));

    if (sToken == "")
    {
        schema_debug_ExitFunction(__FUNCTION__, "sToken is an empty string");
        return "";
    }
    
    string s = r"
        SELECT replace(replace(:token, '~', '~0'), '/', '~1');
    ";
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindString(q, ":token", sToken);
    
    sToken = SqlStep(q) ? SqlGetString(q, 0) : sToken;
    schema_debug_ExitFunction(__FUNCTION__, sToken);
    return sToken;
}

/// @private Construct a pointer string from a json array of pointer segments.
/// @param jaPointer The json array containing the pointer segments.
/// @returns A string representing the pointer, or an empty string if the input is null or empty.
string schema_scope_ConstructPointer(json jaPointer = JSON_NULL)
{
    schema_debug_EnterFunction(__FUNCTION__);

    if (JsonGetType(jaPointer) != JSON_TYPE_ARRAY || JsonGetLength(jaPointer) == 0)
    {
        schema_debug_ExitFunction(__FUNCTION__, "jaPointer is not array");
        return "";
    }

    string sPath;
   
    int i; for (; i < JsonGetLength(jaPointer); i++)
    {
        string sPart = JsonGetString(JsonArrayGet(jaPointer, i));
        sPath += "/" + schema_reference_EscapePointer(sPart);
    }
    
    schema_debug_ExitFunction(__FUNCTION__, sPath);
    return sPath;
}

json schema_scope_DeconstructPath(string sPath)
{
    if (sPath == "") return JsonArray();

    string s = r"
        WITH RECURSIVE split(value, str, i) AS (
            SELECT '', :str || '/', 0
            UNION ALL
            SELECT
                substr(str, 0, instr(str, '/')),
                substr(str, instr(str, '/') + 1),
                i + 1
            FROM split
            WHERE str != ''
        )
        SELECT json_group_array(value) FROM (SELECT value FROM split WHERE str != :str || '/' ORDER BY i);
    ";
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindString(q, ":str", sPath);
    return SqlStep(q) ? SqlGetJson(q, 0) : JsonArray();
}

string schema_scope_ConstructPath(json jaParts, int bAbsolute = FALSE)
{
    if (JsonGetType(jaParts) != JSON_TYPE_ARRAY || JsonGetLength(jaParts) == 0)
        return bAbsolute ? "/" : "";

    string sPath = "";
    int i;
    int nLen = JsonGetLength(jaParts);
    for (i = 0; i < nLen; i++)
    {
        if (i > 0) sPath += "/";
        sPath += JsonGetString(JsonArrayGet(jaParts, i));
    }
    
    if (bAbsolute)
        sPath = "/" + sPath;
        
    return sPath;
}

/// @private Convenience function to construct pointer from lexical scope members.
string schema_scope_ConstructSchemaPath()   {return schema_scope_ConstructPointer(schema_scope_GetSchemaPath());}
string schema_scope_ConstructInstancePath() {return schema_scope_ConstructPointer(schema_scope_GetInstancePath());}

/// @private Convenience functions to modify scope arrays.
void schema_scope_PushLexical(json joScope)      {schema_scope_PushArrayItem("SCHEMA_SCOPE_LEXICAL", joScope);}
void schema_scope_PushDynamic(json joScope)      {schema_scope_PushArrayItem("SCHEMA_SCOPE_DYNAMIC", joScope);}
void schema_scope_PushSchemaPath(string sPath)   {schema_scope_PushArrayItem("SCHEMA_SCOPE_SCHEMAPATH", JsonString(sPath));}
void schema_scope_PushInstancePath(string sPath) {schema_scope_PushArrayItem("SCHEMA_SCOPE_INSTANCEPATH", JsonString(sPath));}
void schema_scope_PushKeymap(json jaScope)       {schema_scope_PushArrayItem("SCHEMA_SCOPE_KEYMAP", jaScope);}

void schema_scope_PushAbsoluteURI(string sURI)
{
    string sKey = "SCHEMA_SCOPE_ABSOLUTE_URI";
    json joEntry = JsonObject();
    JsonObjectSetInplace(joEntry, "uri", JsonString(sURI));
    JsonObjectSetInplace(joEntry, "depth", JsonInt(JsonGetLength(schema_scope_GetSchemaPath())));
    
    schema_scope_PushArrayItem(sKey, joEntry);
}

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
    sqlquery q = schema_core_PrepareModuleQuery(s);
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
        JsonArrayInsertInplace(jaContexts, JsonObjectGet(joScopes, sScopeKey));

    json jaContextItem = JsonArrayGet(jaContexts, JsonGetInt(jIndex));
    if (JsonGetLength(jaContextItem) > 0)
        jaContext = schema_scope_MergeArrays(jaContextItem, jaContext);

    JsonArraySetInplace(jaContexts, JsonGetInt(jIndex), jaContext);
    schema_scope_PushArrayItem(sScopeKey, jaContexts);
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
    if (nLength > 0)
        JsonArraySetInplace(jaPaths, nDepth, JsonArrayDel(jaPath, nLength - 1));
}

/// @private Convenience functions to pop the last member from scope arrays.
void schema_scope_PopLexical()      {schema_scope_Pop("SCHEMA_SCOPE_LEXICAL");}
void schema_scope_PopDynamic()      {schema_scope_Pop("SCHEMA_SCOPE_DYNAMIC");}
void schema_scope_PopSchemaPath()   {schema_scope_Pop("SCHEMA_SCOPE_SCHEMAPATH");}
void schema_scope_PopInstancePath() {schema_scope_Pop("SCHEMA_SCOPE_INSTANCEPATH");}
void schema_scope_PopKeymap()       {schema_scope_Pop("SCHEMA_SCOPE_KEYMAP");}
void schema_scope_PopAbsoluteURI()  {schema_scope_Pop("SCHEMA_SCOPE_ABSOLUTE_URI");}

void schema_scope_PopContext()
{
    schema_scope_Pop("SCHEMA_SCOPE_CONTEXT");
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

string schema_scope_GetBaseURI()
{
    json jaStack = GetLocalJson(GetModule(), "SCHEMA_SCOPE_ABSOLUTE_URI");
    
    // Check if we have an active stack
    if (JsonGetType(jaStack) == JSON_TYPE_ARRAY && JsonGetLength(jaStack) > 0)
    {
        // Get the scope level array for the current depth
        json jaScopeLevel = JsonArrayGet(jaStack, JsonGetLength(jaStack) - 1);
        
        // If we have entries at this level
        if (JsonGetType(jaScopeLevel) == JSON_TYPE_ARRAY && JsonGetLength(jaScopeLevel) > 0)
        {
             // Get the top entry
             json joEntry = JsonArrayGet(jaScopeLevel, JsonGetLength(jaScopeLevel) - 1);
             return JsonGetString(JsonObjectGet(joEntry, "uri"));
        }
    }

    // Fallback: If stack is empty (e.g. root validation start), try Lexical Scope
    json joBase = schema_scope_GetBaseSchema();
    string sBase = JsonGetString(JsonObjectGet(joBase, "$id"));
    if (sBase == "") sBase = JsonGetString(JsonObjectGet(joBase, "id"));
    return sBase;
}

string schema_scope_GetAbsoluteKeywordLocation()
{
    json jaStack = GetLocalJson(GetModule(), "SCHEMA_SCOPE_ABSOLUTE_URI");
    
    if (JsonGetType(jaStack) != JSON_TYPE_ARRAY || JsonGetLength(jaStack) == 0)
    {
        // Fallback: Use Base Schema ID + Current Fragment (assuming we are at root depth 0 relative to base)
        json joBase = schema_scope_GetBaseSchema();
        string sBase = JsonGetString(JsonObjectGet(joBase, "$id"));
        if (sBase == "") sBase = JsonGetString(JsonObjectGet(joBase, "id"));
        return sBase + "#" + schema_scope_ConstructSchemaPath();
    }

    // Get the scope level array for the current depth
    json jaScopeLevel = JsonArrayGet(jaStack, JsonGetLength(jaStack) - 1);
    
    // If no URI pushed at this scope level, fallback
    if (JsonGetType(jaScopeLevel) != JSON_TYPE_ARRAY || JsonGetLength(jaScopeLevel) == 0)
    {
         json joBase = schema_scope_GetBaseSchema();
         string sBase = JsonGetString(JsonObjectGet(joBase, "$id"));
         if (sBase == "") sBase = JsonGetString(JsonObjectGet(joBase, "id"));
         return sBase + "#" + schema_scope_ConstructSchemaPath();
    }

    // Get the top entry from the stack at this scope level
    json joEntry = JsonArrayGet(jaScopeLevel, JsonGetLength(jaScopeLevel) - 1);
    
    string sBase = JsonGetString(JsonObjectGet(joEntry, "uri"));
    int nBaseDepth = JsonGetInt(JsonObjectGet(joEntry, "depth"));
    
    json jaCurrentPath = schema_scope_GetSchemaPath();
    int nCurrentDepth = JsonGetLength(jaCurrentPath);
    
    // If the saved URI already has a fragment, sBase includes it (e.g. "...#/defs/A")
    // We append the path segments that were added SINCE the push.
    
    string sFragment = "";
    int i; 
    for (i = nBaseDepth; i < nCurrentDepth; i++)
    {
         string sPart = JsonGetString(JsonArrayGet(jaCurrentPath, i));
         sFragment += "/" + schema_reference_EscapePointer(sPart);
    }
    
    // Ensure fragment separator if needed
    if (sFragment != "" && FindSubString(sBase, "#") == -1)
        sBase += "#";

    return sBase + sFragment;
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
        return "instance not found in enum";
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
    else if (sError == "<validate_mincontains>")
        return "instance contains less than minContains";
    else if (sError == "<validate_maxcontains>")
        return "instance contains more than maxContains";
    else if (sError == "<validate_unevaluateditems>")
        return "<@todo>";
    else if (sError == "<validate_required>")
        return "instance missing required properties";
    else if (sError == "<validate_minproperties>")
        return "instance has less than minProperties";
    else if (sError == "<validate_maxproperties>")
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

void schema_output_SetValid(json joOutputUnit, int bValid = TRUE)
{
    JsonObjectSetInplace(joOutputUnit, "valid", bValid ? JSON_TRUE : JSON_FALSE);
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
        sSchemaID = "https://json-schema.org/draft/2020-12/output/schema";

    schema_core_CreateTables();

    /// @brief If previously built, the output unit at the desired verbosity level will
    ///     exist in the schema output table.
    string s = r"
        SELECT output
        FROM $schema_output
        WHERE verbosity = :verbosity
            AND schema_id = :schema_id;
    ";
    sqlquery q = schema_core_PrepareCampaignQuery(s);
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

    q = schema_core_PrepareModuleQuery(s);
    SqlBindString(q, ":verbosity", sVerbosity);
    SqlBindJson(q, ":schema", joSchema);
    
    if (SqlStep(q))
    {
        json joOutputUnit = SqlGetJson(q, 0);
        if (JsonGetType(joOutputUnit) != JSON_TYPE_OBJECT)
            return JsonObject();

        string s = r"
            INSERT INTO $schema_output (verbosity, schema, output)
            VALUES (:verbosity, :schema, :output)
            ON CONFLICT(verbosity, schema) DO UPDATE SET
                output = :output;
        ";
        sqlquery q = schema_core_PrepareCampaignQuery(s);
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
void schema_output_SetKeywordLocation(json joOutputUnit)
{
    schema_debug_EnterFunction(__FUNCTION__);
    JsonObjectSetInplace(joOutputUnit, "keywordLocation", JsonString(schema_scope_ConstructSchemaPath()));
    schema_debug_ExitFunction(__FUNCTION__);
}

/// @private Set the `instanceLocation` value into joOutputUnit by constructing the current instance
///     path from the instance path scope.
void schema_output_SetInstanceLocation(json joOutputUnit)
{
    schema_debug_EnterFunction(__FUNCTION__);
    JsonObjectSetInplace(joOutputUnit, "instanceLocation", JsonString(schema_scope_ConstructInstancePath()));
    schema_debug_ExitFunction(__FUNCTION__);
}

/// @private Set the `absoluteKeywordLocation` value into joOutputUnit by constructing the current
///     absolute schema path from the absolute schema path scope.  If an absolute URI cannot be
///     be resolved due to the lack of an $id or references that only use #, the key will not
///     be added.
void schema_output_SetAbsoluteKeywordLocation(json joOutputUnit)
{
    string sLoc = schema_scope_GetAbsoluteKeywordLocation();
    // Only output if it's a full URI (e.g. has scheme)
    if (FindSubString(sLoc, ":") != -1)
        JsonObjectSetInplace(joOutputUnit, "absoluteKeywordLocation", JsonString(sLoc));
}

/// @private Build an output unit skeleton.  keywordLocation and instanceLocation are populated here
///     for use by parent nodes.  Child nodes will have these values overwritten as annotations and
///     errors are added.
/// @note keyword valid is set to TRUE here even though the query in schema_output_GetMinimalObject()
///     specifies a value of `true` as the value is sometimes translated to integer 1 and no longer
///     recognized as boolean for comparison purposes.
json schema_output_GetOutputUnit(string sSource = "")
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sSource", JsonString(sSource));

    json joOutputUnit = schema_output_GetMinimalObject();
    schema_output_SetKeywordLocation(joOutputUnit);
    schema_output_SetInstanceLocation(joOutputUnit);
    schema_output_SetAbsoluteKeywordLocation(joOutputUnit);
    schema_output_SetValid(joOutputUnit, TRUE);

    if (SCHEMA_OUTPUT_INCLUDE_SOURCE)
    {
        if (sSource == "") 
            JsonObjectSetInplace(joOutputUnit, "source", JsonString("default"));
        else
            JsonObjectSetInplace(joOutputUnit, "source", JsonString(" :: " + sSource + " :: "));
    }

    if (SCHEMA_OUTPUT_INCLUDE_UUID)
        JsonObjectSetInplace(joOutputUnit, "uuid", JsonString(GetRandomUUID()));

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @private Insert an error object into the parent node's errors array.
void schema_output_InsertError(json joOutputUnit, json joError, string sSource = "")
{
    if (JsonGetType(joError) != JSON_TYPE_OBJECT)
        return;

    json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    if (JsonGetType(jaErrors) != JSON_TYPE_ARRAY)
        jaErrors = JsonArray();

    JsonArrayInsertInplace(jaErrors, joError);
    JsonObjectSetInplace(joOutputUnit, "errors", jaErrors);
    schema_output_SetValid(joOutputUnit, FALSE);

    if (SCHEMA_OUTPUT_INCLUDE_SOURCE && sSource != "")
        JsonObjectSetInplace(joOutputUnit, "source", JsonString(sSource));

    /// @todo Why is this here and in InsertAnnotation?
    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joOutputUnit); 
}

/// @private Insert an annotation object into the parent node's annotations array.
void schema_output_InsertAnnotation(json joOutputUnit, json joAnnotation, string sSource = "")
{
    if (JsonGetType(joAnnotation) != JSON_TYPE_OBJECT)
        return;

    json jaAnnotations = JsonObjectGet(joOutputUnit, "annotations");
    if (JsonGetType(jaAnnotations) != JSON_TYPE_ARRAY)
        jaAnnotations = JsonArray();

    JsonArrayInsertInplace(jaAnnotations, joAnnotation);
    JsonObjectSetInplace(joOutputUnit, "annotations", jaAnnotations);

    json jaErrors = JsonObjectGet(joOutputUnit, "errors");
    int bValid = JsonGetType(jaErrors) == JSON_TYPE_ARRAY && JsonGetLength(jaErrors) > 0;
        
    schema_output_SetValid(joOutputUnit, !bValid);
    SetLocalJson(GetModule(), "SCHEMA_VALIDATION_RESULT", joOutputUnit); 

    if (SCHEMA_OUTPUT_INCLUDE_SOURCE && sSource != "")
        JsonObjectSetInplace(joOutputUnit, "source", JsonString(sSource));
}

/// @todo
///     [ ] how do we handle failed keyword validations that may not fail the entire schema?

/// @private Insert an error string in an output unit.
void schema_output_SetError(json joOutputUnit, string sError, string sSource = "")
{
    JsonObjectSetInplace(joOutputUnit, "error", JsonString(sError));
    schema_output_SetKeywordLocation(joOutputUnit);
    schema_output_SetInstanceLocation(joOutputUnit);
    
    if (SCHEMA_OUTPUT_INCLUDE_SOURCE && sSource != "")
        JsonObjectSetInplace(joOutputUnit, "source", JsonString(sSource));

    schema_output_SetValid(joOutputUnit, FALSE);
}

/// @private Insert an annotation key:value pair into an output unit.
void schema_output_SetAnnotation(json joOutputUnit, string sKey, json jValue, string sSource = "")
{
    JsonObjectSetInplace(joOutputUnit, sKey, jValue);
    schema_output_SetKeywordLocation(joOutputUnit);
    schema_output_SetInstanceLocation(joOutputUnit);

    if (SCHEMA_OUTPUT_INCLUDE_SOURCE && sSource != "")
        JsonObjectSetInplace(joOutputUnit, "source", JsonString(sSource));
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
    sqlquery q = schema_core_PrepareModuleQuery(s);
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
//    sqlquery q = schema_core_PrepareCampaignQuery(s);
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
void schema_output_InsertResult(json joOutputUnit, json joResult, string sSource)
{
    if (schema_output_GetValid(joResult))
        schema_output_InsertAnnotation(joOutputUnit, joResult, sSource);
    else
        schema_output_InsertError(joOutputUnit, joResult, sSource);
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

    sqlquery q = schema_core_PrepareModuleQuery(s);
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

    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindJson(q, ":output", joOutputUnit);

    return SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
}




/// @note The following utility functions are meant to replace the nwscript-functions of a similar
///     name.  These functions allow the use of non-ascii characters within strings and successfully
///     match, identify, or return the correct non-ascii character interpretation of the string
///     value.

/// @private Determine if sString matches regex sPattern.
int schema_validate_RegExpMatch(string sPattern, string sString)
{
    string s = r"
        SELECT 1
        WHERE
            CAST(CAST(json_extract(json(:string), '$') AS BLOB) AS TEXT)
            REGEXP
            CAST(CAST(json_extract(json(:pattern), '$') AS BLOB) AS TEXT);
    ";
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindJson(q, ":string", JsonString(sString));
    SqlBindJson(q, ":pattern", JsonString(sPattern));
    return SqlStep(q);
}

/// @private Retrieve the converted value of sKey from jObject.
json schema_validate_JsonObjectGet(json jObject, string sKey)
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
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindJson(q, ":obj", jObject);
    SqlBindJson(q, ":key", JsonString(sKey));
    
    return SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
}

/// @private Determine if sKey exists in jObject.
int schema_validate_HasKey(json jObject, string sKey)
{
    if (JsonGetType(JsonObjectGet(jObject, sKey)) != JSON_TYPE_NULL) return TRUE;

    string s = r"
        SELECT 1 FROM json_each(:obj)
        WHERE CAST(CAST(key AS BLOB) AS TEXT) = CAST(CAST(json_extract(json(:key), '$') AS BLOB) AS TEXT);
    ";
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindJson(q, ":obj", jObject);
    SqlBindJson(q, ":key", JsonString(sKey));
    
    return SqlStep(q) ? SqlGetInt(q, 0) : FALSE;
}

/// -----------------------------------------------------------------------------------------------
///                                     REFERENCE MANAGEMENT
/// -----------------------------------------------------------------------------------------------
/// @brief Schema reference management functions.  These functions provide a method for identifying,
///     resolving and utilizing $anchor, $dynamicAnchor, $ref and $dynamicRef keywords.

/// @private Normalize a path by removing dot-segments as per RFC 3986 Section 5.2.4.
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

/// @private Normalize a path that contains empty segments, or hierarchical segments such as
///     "." and "..".
/// @param sPath The path to normalize.
/// @returns A normalized path string with empty segments and hierarchical segments resolved.
string schema_reference_NormalizePath(string sPath)
{
    if (sPath == "") return "";

    int bAbsolute = (GetStringLeft(sPath, 1) == "/");
    json jaParts = schema_scope_DeconstructPath(sPath);
    json jaStack = JsonArray();
    
    int n = JsonGetLength(jaParts);
        int i; for (; i < n; i++)
    {
        string sPart = JsonGetString(JsonArrayGet(jaParts, i));
        
        if (sPart == "" || sPart == ".")
            continue;
            
        if (sPart == "..")
        {
            int nStackLen = JsonGetLength(jaStack);
            if (nStackLen > 0)
            {
                string sTop = JsonGetString(JsonArrayGet(jaStack, nStackLen - 1));
                if (sTop == "..")
                    JsonArrayInsertInplace(jaStack, JsonString(sTop));
                else
                {
                    // Pop
                    json jaNew = JsonArray();
                    int j; for (; j < nStackLen - 1; j++)
                        JsonArrayInsertInplace(jaNew, JsonArrayGet(jaStack, j));
                    
                    jaStack = jaNew;
                }
            }
            else if (!bAbsolute)
                JsonArrayInsertInplace(jaStack, JsonString(".."));
        }
        else
            JsonArrayInsertInplace(jaStack, JsonString(sPart));
    }
    
    return schema_scope_ConstructPath(jaStack, bAbsolute);
}

/// @private Resolve a relative URI against a base URI.
string schema_reference_ResolveURI(string sBaseURI, string sRelativeURI)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sBaseURI", JsonString(sBaseURI));
    schema_debug_Argument(__FUNCTION__, "sRelativeURI", JsonString(sRelativeURI));

    string sTargetURI;

    if (sRelativeURI == "" || sRelativeURI == "#")
    {
        schema_debug_ExitFunction(__FUNCTION__, "sRelativeURI is an empty string or a self-reference ('#')");
        return sBaseURI;
    }

    // Regex for URI parsing (RFC 3986)
    string r = "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?$";
    json jaMatchRef = RegExpMatch(r, sRelativeURI);
    
    // If relative URI is absolute (has scheme), return it
    if (JsonGetString(JsonArrayGet(jaMatchRef, 2)) != "")
    {
        // Even if absolute, we must normalize the path (RFC 3986 5.2.2)
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 1)); // Scheme
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 3)); // Authority
        sTargetURI += schema_reference_NormalizePath(JsonGetString(JsonArrayGet(jaMatchRef, 5))); // Path
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 6)); // Query
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchRef, 8)); // Fragment
        
        schema_debug_ExitFunction(__FUNCTION__, "sRelativeURI has a schema; returning normalized");
        return sTargetURI;
    }

    json jaMatchBase = RegExpMatch(r, sBaseURI);

    if (JsonGetString(JsonArrayGet(jaMatchRef, 3)) != "") // Authority (//...)
    {
        sTargetURI += JsonGetString(JsonArrayGet(jaMatchBase, 1)); // Base Scheme (RFC 3986 5.2.2)
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
    schema_debug_ExitFunction(__FUNCTION__, sTargetURI);
    return sTargetURI;
}

/// @private Unescape a JSON pointer string (~1 -> /, ~0 -> ~)
string schema_reference_UnescapePointer(string sPointer)
{
    if (sPointer == "") return "";

    string s = "SELECT replace(replace(:pointer, '~1', '/'), '~0', '~')";
    sqlquery q = schema_core_PrepareModuleQuery(s);
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
    string s = "SELECT hex(:uri)";
    sqlquery q = schema_core_PrepareModuleQuery(s);
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
    s = "SELECT CAST(x'" + sResultHex + "' AS TEXT)";
    q = schema_core_PrepareModuleQuery(s);
    
    return SqlStep(q) ? SqlGetString(q, 0) : sURI;
}

json schema_reference_ResolveAnchor(json joSchema, string sAnchor)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sAnchor", JsonString(sAnchor));

    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT || sAnchor == "")
    {
        schema_debug_ExitFunction(__FUNCTION__, "instance type is not object or sAnchor is an empty string");
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
                WHERE key IN ('$anchor', '$dynamicAnchor') AND atom = :anchor
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

    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindString(q, ":anchor", sAnchor);

    json jResult = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    schema_debug_ExitFunction(__FUNCTION__, JsonDump(jResult));
    return jResult;
}

json schema_reference_ResolvePointer(json joSchema, string sPointer)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "joSchema", joSchema);
    schema_debug_Argument(__FUNCTION__, "sPointer", JsonString(sPointer));

    if (sPointer == "")
    {
        schema_debug_ExitFunction(__FUNCTION__, "sPointer is empty");
        return joSchema;
    }

    // If the pointer is just "/", it resolves to the root
    if (sPointer == "/")
    {
        schema_debug_ExitFunction(__FUNCTION__, "sPointer is root");
        return joSchema;
    }

    json jaParts = schema_scope_DeconstructPointer(sPointer);
    json jCurrent = joSchema;
    int i, n = JsonGetLength(jaParts);

    for (i = 0; i < n; i++)
    {
        string sPart = JsonGetString(JsonArrayGet(jaParts, i));
        sPart = schema_reference_UnescapePointer(sPart);

        int nType = JsonGetType(jCurrent);
        if (nType == JSON_TYPE_OBJECT)
        {
            if (!schema_validate_HasKey(jCurrent, sPart))
            {
                schema_debug_ExitFunction(__FUNCTION__, "schema does not have desired key");
                return JsonNull();
            }
            jCurrent = schema_validate_JsonObjectGet(jCurrent, sPart);
        }
        else if (nType == JSON_TYPE_ARRAY)
        {
            int nIndex = StringToInt(sPart);
            // Check if sPart is a valid integer string and within bounds
            if (IntToString(nIndex) != sPart || nIndex < 0 || nIndex >= JsonGetLength(jCurrent))
            {
                schema_debug_ExitFunction(__FUNCTION__, "sPart is not a valid integer string within bounds");
                return JsonNull();
            }
            jCurrent = JsonArrayGet(jCurrent, nIndex);
        }
        else
        {
            schema_debug_ExitFunction(__FUNCTION__, "nType is not valid; returning null");
            return JsonNull();
        }
    }

    schema_debug_ExitFunction(__FUNCTION__, JsonDump(jCurrent));
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
        DELETE FROM $schema_schema
        WHERE schema_id = :schema_id;
    ";
    sqlquery q = schema_core_PrepareCampaignQuery(s);
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
        sID = JsonGetString(JsonObjectGet(joSchema, "id"));

    if (sID == "")
        return;

    json jaKeyMap = schema_keyword_GetMap(sID, joSchema, TRUE);

    string s = r"
        INSERT INTO $schema_schema (schema, keymap)
        VALUES (:schema, :keymap);
    ";
    sqlquery q = schema_core_PrepareCampaignQuery(s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindJson(q, ":keymap", jaKeyMap);
    SqlStep(q);
}

/// @brief Iterates through all schemas in the database and forces a regeneration of their keymaps.
/// @note This is useful for development and testing when the keymap logic has changed.
void schema_reference_RebuildKeymaps()
{
    schema_core_CreateTables();

    string s = r"
        SELECT json_group_array(schema_id) FROM $schema_schema;
    ";
    sqlquery q = schema_core_PrepareCampaignQuery(s);
    json jaIDs = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();

    if (JsonGetType(jaIDs) != JSON_TYPE_ARRAY)
        return;

    int i; for (; i < JsonGetLength(jaIDs); i++) 
    {
        string sID = JsonGetString(JsonArrayGet(jaIDs, i));
        json jaKeyMap = schema_keyword_GetMap(sID, JSON_NULL, TRUE);

        s = r"
            UPDATE $schema_schema SET keymap = :keymap WHERE schema_id = :id
        ";
        q = schema_core_PrepareCampaignQuery(s);
        SqlBindJson(q, ":keymap", jaKeyMap);
        SqlBindString(q, ":id", sID);
        SqlStep(q);
    }
}

json schema_reference_GetSchema(string sSchemaID)
{
    if (sSchemaID == "")
        return JsonNull();

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
        FROM $schema_schema
        WHERE schema_id = :id
            OR schema_id = :id || '#';
    ";
    sqlquery q = schema_core_PrepareCampaignQuery(s);
    SqlBindString(q, ":id", sSchemaID);

    json joSchema = SqlStep(q) ? SqlGetJson(q, 0) : JsonNull();
    if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
        return joSchema;

    return JsonNull();
}

/// @private Resolve a fragment reference within a $ref.
/// @param joSchema The base schema to resolve the fragment against.
/// @param sFragment The fragment string to resolve.
/// @returns The resolved fragment, or JsonNull() if the fragment
///     could not be resolved.
json schema_reference_ResolveFragment(json joSchema, string sFragment)
{
    schema_debug_EnterFunction(__FUNCTION__);

    sFragment = schema_reference_DecodeURI(sFragment);

    if (GetStringLeft(sFragment, 1) == "/")
    {
        json jResult = schema_reference_ResolvePointer(joSchema, sFragment);
        schema_debug_ExitFunction(__FUNCTION__, "sFragment is a pointer");
        return jResult;
    }
    else if (sFragment == "")
    {
        schema_debug_ExitFunction(__FUNCTION__, "sFragment is empty");
        return joSchema;
    }
    else
    {
        json joAnchor = schema_reference_ResolveAnchor(joSchema, sFragment);
        schema_debug_ExitFunction(__FUNCTION__, JsonDump(joAnchor));
        return joAnchor;
    }
}

/// @private Resolve a $ref.  This function follows closesly the uri resolution
///     algorithm defined in RFC 3986, Section 5.2.  It handles both absolute and
///     relative references, as well as fragment-only references.
/// @param joSchema The base schema to resolve the reference against.
/// @param jsRef The $ref json object to resolve.
/// @returns The resolved schema, or the base schema if no resolution is possible.
json schema_reference_ResolveRef(json joSchema, json jsRef)
{
    schema_debug_EnterFunction(__FUNCTION__);

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
    {
        // Check if the schema is already in the current ID map (internal reference)
        json joCurrentIDMap = GetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP");
        if (JsonGetType(joCurrentIDMap) == JSON_TYPE_OBJECT)
        {
            json joMapped = JsonObjectGet(joCurrentIDMap, sSchemaID);
            if (JsonGetType(joMapped) == JSON_TYPE_OBJECT)
                joTargetSchema = joMapped;
        }

        if (JsonGetType(joTargetSchema) == JSON_TYPE_NULL)
            joTargetSchema = schema_reference_GetSchema(sSchemaID);
    }
    
    if (JsonGetType(joTargetSchema) == JSON_TYPE_NULL)
    {
        schema_debug_ExitFunction(__FUNCTION__, "joTargetSchema is null");
        return JsonNull();
    }

    if (sFragment == "")
    {
        schema_debug_ExitFunction(__FUNCTION__, "sFragment is an empty string");
        return joTargetSchema;
    }
        
    json jResult = schema_reference_ResolveFragment(joTargetSchema, sFragment);
    schema_debug_ExitFunction(__FUNCTION__);
    return jResult;
}

/// @todo
///     [ ] See who is receiving the JsonNull() and handle it.

/// @private Resolve a dynamic anchor subschema from the current dynamic scope.
/// @param jsRef The dynamic anchor to resolve.
/// @returns The resolved dynamic anchor schema as a json object, or an empty
///     json object if not found.
json schema_reference_ResolveDynamicRef(json joSchema, json jsRef, int bRevertToRef = FALSE)
{
    // 1. Static Resolution
    json joStatic = schema_reference_ResolveRef(joSchema, jsRef);
    
    if (JsonGetType(joStatic) == JSON_TYPE_NULL)
        return JsonNull();

    // If the static resolution is not an object (e.g. boolean schema), it cannot have a dynamic anchor,
    // so we treat it as a normal ref and return the static resolution.
    if (JsonGetType(joStatic) != JSON_TYPE_OBJECT)
        return joStatic;

    // 2. Check if Static Resolution has the matching dynamic anchor
    string sRef = JsonGetString(jsRef);
    string sAnchor = sRef;
    int nHash = FindSubString(sRef, "#");
    if (nHash != -1)
        sAnchor = GetStringRight(sRef, GetStringLength(sRef) - nHash - 1);
    
    json jsAnchorName = JsonString(sAnchor);
    json jsStaticAnchor = JsonObjectGet(joStatic, "$dynamicAnchor");

    // If the static target is not a dynamic anchor, return it as a static ref
    if (jsStaticAnchor != jsAnchorName)
        return joStatic;

    // 3. Dynamic Scope Search (Outermost -> Innermost)
    json jaDynamicStack = GetLocalJson(GetModule(), "SCHEMA_SCOPE_DYNAMIC");
    if (JsonGetType(jaDynamicStack) == JSON_TYPE_ARRAY)
    {
        int nDepth;
        for (nDepth = 0; nDepth < JsonGetLength(jaDynamicStack); nDepth++)
        {
            json jaScopeLevel = JsonArrayGet(jaDynamicStack, nDepth);
            if (JsonGetType(jaScopeLevel) != JSON_TYPE_ARRAY) continue;

            int i;
            for (i = 0; i < JsonGetLength(jaScopeLevel); i++)
            {
                json joScope = JsonArrayGet(jaScopeLevel, i);
                
                // We must use ResolveAnchor because the anchor might be deep inside the scope resource
                json joDynamicMatch = schema_reference_ResolveAnchor(joScope, sAnchor);
                if (JsonGetType(joDynamicMatch) == JSON_TYPE_OBJECT)
                {
                    // Ensure it is actually a dynamic anchor
                    if (JsonObjectGet(joDynamicMatch, "$dynamicAnchor") == jsAnchorName)
                        return joDynamicMatch;
                }
            }
        }
    }

    return joStatic;
}

string schema_reference_ResolveDynamicRefURI(json joSchema, json jsRef)
{
    // Duplicate logic to find the URI
    string sStaticURI = "";
    
    // Calculate Static URI logic (simplified from ResolveRef)
    json joBaseSchema = schema_scope_GetBaseSchema();
    string sRef = JsonGetString(jsRef);
    
    string sBaseURI = JsonGetString(JsonObjectGet(joBaseSchema, "$id"));
    if (sBaseURI == "") sBaseURI = JsonGetString(JsonObjectGet(joBaseSchema, "id"));
    sStaticURI = schema_reference_ResolveURI(sBaseURI, sRef);

    // If it's just a static ref disguised as dynamic (no anchor or different anchor), return static
    // We need to resolve the object to check the anchor presence efficiently, but we can't easily 
    // unless we call ResolveRef. 
    // Optimization: If ResolveDynamicRef returns the static object (by comparing IDs or pointers?), we use StaticURI.
    // However, we can just run the dynamic search.

    string sAnchor = sRef;
    int nHash = FindSubString(sRef, "#");
    if (nHash != -1)
        sAnchor = GetStringRight(sRef, GetStringLength(sRef) - nHash - 1);

    json jsAnchorName = JsonString(sAnchor);

    // Dynamic Scope Search
    json jaDynamicStack = GetLocalJson(GetModule(), "SCHEMA_SCOPE_DYNAMIC");
    if (JsonGetType(jaDynamicStack) == JSON_TYPE_ARRAY)
    {
        int nDepth;
        for (nDepth = 0; nDepth < JsonGetLength(jaDynamicStack); nDepth++)
        {
            json jaScopeLevel = JsonArrayGet(jaDynamicStack, nDepth);
            if (JsonGetType(jaScopeLevel) != JSON_TYPE_ARRAY) continue;

            int i;
            for (i = 0; i < JsonGetLength(jaScopeLevel); i++)
            {
                json joScope = JsonArrayGet(jaScopeLevel, i);
                json joDynamicMatch = schema_reference_ResolveAnchor(joScope, sAnchor);
                
                if (JsonGetType(joDynamicMatch) == JSON_TYPE_OBJECT)
                {
                   if (JsonObjectGet(joDynamicMatch, "$dynamicAnchor") == jsAnchorName)
                   {
                       // Found match in dynamic scope. Construct URI.
                       string sScopeID = JsonGetString(JsonObjectGet(joScope, "$id"));
                       if (sScopeID == "") sScopeID = JsonGetString(JsonObjectGet(joScope, "id"));
                       
                       // If scope has no ID, it might be an internal subschema pushed dynamically.
                       // We can try to use the static URI? No.
                       // Use the ID if present.
                       if (sScopeID != "")
                           return sScopeID + "#" + sAnchor;
                   }
                }
            }
        }
    }

    return sStaticURI;
}

json schema_reference_ResolveRecursiveRef(json joSchema)
{
    json jaDynamic = schema_scope_GetDynamic();
    json jRef = JsonObjectGet(joSchema, "$recursiveRef");
    json joTarget = schema_reference_ResolveRef(joSchema, jRef);

    if (JsonGetType(joTarget) == JSON_TYPE_NULL)
        return JsonNull();

    json jsAnchor = JsonObjectGet(joTarget, "$recursiveAnchor");
    if (JsonGetType(jsAnchor) != JSON_TYPE_BOOL || jsAnchor != JSON_TRUE)
        return joTarget;

    if (JsonGetType(jaDynamic) != JSON_TYPE_ARRAY || JsonGetLength(jaDynamic) == 0)
        return joTarget;

    json jaSchema = JsonArrayGet(jaDynamic, schema_scope_GetDepth());
    if (JsonGetType(jaSchema) != JSON_TYPE_ARRAY || JsonGetLength(jaSchema) == 0)
        return joTarget;

    int i; for (i = 0; i < JsonGetLength(jaSchema); i++)
    {
        json joScope = JsonArrayGet(jaSchema, i);
        json jsScopeAnchor = JsonObjectGet(joScope, "$recursiveAnchor");
        if (JsonGetType(jsScopeAnchor) == JSON_TYPE_BOOL && jsScopeAnchor == JSON_TRUE)
            return joScope;
    }

    return joTarget;
}

/// -----------------------------------------------------------------------------------------------
///                                     KEYWORD MANAGEMENT
/// -----------------------------------------------------------------------------------------------

/// @private Recursive helper to collect keywords during the schema save process.
/// @note Keywords are collected from the members of the `properties` object of
///     the subject schema as well as the `properties` objects of any schema found
///     in the subject schema's `allOf` value.
json schema_keyword_Collect(json joSchema, string sBaseURI, json jaSeen, json jaKeywords, json joVocabulary)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sBaseURI", JsonString(sBaseURI));
    schema_debug_Argument(__FUNCTION__, "jaSeen", jaSeen);
    schema_debug_Argument(__FUNCTION__, "jaKeywords", jaKeywords);

    json joLocalVocabulary = JsonObjectGet(joSchema, "$vocabulary");
    if (JsonGetType(joLocalVocabulary) == JSON_TYPE_OBJECT)
        joVocabulary = joLocalVocabulary;

    string s = r"
        SELECT json_group_array(DISTINCT value)
        FROM (
            SELECT value FROM json_each(:keywords)
            UNION
            SELECT key as value
            FROM json_each(COALESCE(json_extract(:schema, '$.properties'), '{}'))
        );
    ";
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindJson(q, ":schema", joSchema);
    SqlBindJson(q, ":keywords", jaKeywords);
    
    if (SqlStep(q))
        jaKeywords = SqlGetJson(q, 0);

    json jaAllOf = JsonObjectGet(joSchema, "allOf");
    if (JsonGetType(jaAllOf) == JSON_TYPE_ARRAY)
    {
        int i; for (; i < JsonGetLength(jaAllOf); i++)
        {
            json joItem = JsonArrayGet(jaAllOf, i);
            json jRef = JsonObjectGet(joItem, "$ref");

            if (JsonGetType(jRef) == JSON_TYPE_STRING)
            {
                string sRef = JsonGetString(jRef);
                string sResolvedURI = schema_reference_ResolveURI(sBaseURI, sRef);
                
                if (JsonFind(jaSeen, JsonString(sResolvedURI)) == JsonNull())
                {
                    JsonArrayInsertInplace(jaSeen, JsonString(sResolvedURI));
                    
                    json joTarget = schema_reference_GetSchema(sResolvedURI);
                    if (JsonGetType(joTarget) == JSON_TYPE_OBJECT)
                    {
                        string sTargetID = JsonGetString(JsonObjectGet(joTarget, "$id"));
                        if (sTargetID == "") sTargetID = JsonGetString(JsonObjectGet(joTarget, "id"));
                        if (sTargetID == "") sTargetID = sResolvedURI;
                        
                        if (sTargetID != sResolvedURI && JsonGetType(joVocabulary) == JSON_TYPE_OBJECT)
                        {
                            json jVocab = JsonObjectGet(joVocabulary, sTargetID);
                            if (JsonGetType(jVocab) == JSON_TYPE_BOOL && jVocab == JSON_FALSE)
                                continue;
                        }
                        
                        jaKeywords = schema_keyword_Collect(joTarget, sTargetID, jaSeen, jaKeywords, joVocabulary);
                    }
                }
            }
            else
                jaKeywords = schema_keyword_Collect(joItem, sBaseURI, jaSeen, jaKeywords, joVocabulary);
        }
    }

    schema_debug_ExitFunction(__FUNCTION__, IntToString(JsonGetLength(jaKeywords)) + " keyword(s) collected");
    return jaKeywords;
}

/// @private Retrieve or createaa keymap for the specified schema.
/// @note Keymaps are used as a shortcut to determine keyword applicability to any schema.
///     If the schema is saved to the databsae, the keymap is also saved.  Though rarely
///     needed, keymaps can be refreshed by reloading the schema.
/// @see schema_reference_RebuildKeymaps().
json schema_keyword_GetMap(string sSchemaID, json joSchema = JSON_NULL, int bForce = FALSE)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sSchemaID", JsonString(sSchemaID));
    schema_debug_Argument(__FUNCTION__, "joSchema", joSchema);
    schema_debug_Argument(__FUNCTION__, "bForce", JsonBool(bForce));

    // Try to retrieve from the database first if an ID is provided and not forced
    if (!bForce && sSchemaID != "")
    {
        string s = r"
            SELECT keymap
            FROM $schema_schema
            WHERE schema_id = :id;
        ";
        sqlquery q = schema_core_PrepareCampaignQuery(s);
        SqlBindString(q, ":id", sSchemaID);
        
        if (SqlStep(q))
        {
            json joMap = SqlGetJson(q, 0);
            if (JsonGetType(joMap) == JSON_TYPE_ARRAY)
            {
                schema_debug_ExitFunction(__FUNCTION__, "keymap found in database");
                return joMap;
            }
        }
    }

    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
        joSchema = schema_reference_GetSchema(sSchemaID);

    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
    {  
        schema_debug_ExitFunction(__FUNCTION__, "non-object schema found in database");
        return JsonArray();
    }

    json jaSeen = JsonArray();
    if (sSchemaID != "") JsonArrayInsertInplace(jaSeen, JsonString(sSchemaID));
    
    // Use an array to accumulate keywords
    json joVocabulary = JsonObjectGet(joSchema, "$vocabulary");
    json j = schema_keyword_Collect(joSchema, sSchemaID, jaSeen, JsonArray(), joVocabulary);

    schema_debug_ExitFunction(__FUNCTION__);
    return j;
}

/// @brief Checks if a keyword is active in the current scope's keymap.
/// @param sKeyword The keyword to check.
/// @returns TRUE if the keyword is active (found in the keymap), FALSE otherwise.
int schema_keyword_IsActive(string sKeyword)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "sKeyword", JsonString(sKeyword));

    json jaMapStack = schema_scope_GetKeymap();
    if (JsonGetType(jaMapStack) != JSON_TYPE_ARRAY || JsonGetLength(jaMapStack) == 0)
    {
        schema_debug_ExitFunction(__FUNCTION__, "keymap does not exist");
        return FALSE;
    }

    json jaKeyMap = JsonArrayGet(jaMapStack, JsonGetLength(jaMapStack) - 1);
    if (JsonGetType(jaKeyMap) != JSON_TYPE_ARRAY)
    {
        schema_debug_ExitFunction(__FUNCTION__, "keymap is not array");
        return FALSE;
    }
    
    int bFound = JsonFind(jaKeyMap, JsonString(sKeyword)) != JsonNull();
    schema_debug_ExitFunction(__FUNCTION__, sKeyword + " is" + (bFound ? "" : " not") + " active");
    return bFound;
}

int schema_keyword_IsLegacy()
{
    return !schema_keyword_IsActive("unevaluatedItems");
}

int schema_keyword_IsModern()
{
    return !schema_keyword_IsLegacy();
}

int schema_keyword_Annotate()
{
    return schema_keyword_IsActive("unevaluatedItems");
}

int schema_keyword_GetDraft()
{
    /// @todo
    ///     use keyword availability to determine which draft we're in and return the draft
    ///     number 4, 6, 7, 2019, 2020, etc.  For early drafts, return the draft #, for later
    ///     drafts, return the year.  This keep them in order and probably a good assumption
    ///     there won't be more than one draft released in any specific year.

    return 0;
}

/// -----------------------------------------------------------------------------------------------
///                                     KEYWORD VALIDATION
/// -----------------------------------------------------------------------------------------------

/// @private `type`.  The value of `type` must be either a string or an array of unique strings.  String values
///     must be one of the primitive types (null, boolean, object, array, number, string or integer).  The
///     integer value implies that floating point numbers with a zero fraction portion are equivalent to integers.
///     Successful validation occurs when:
///     - if the schema is a string, the instance's type matches the type represented by the value of the string.
///     - if the schema is an array, the instance's type matches any of teh types contained within the array.
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
            schema_debug_Message("schema -> number");
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
            {
                schema_debug_ExitFunction(__FUNCTION__, "instance type is number");
                schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
                return joOutputUnit;
            }
        }
        else if (JsonGetString(jSchema) == "integer")
        {
            if (nInstanceType == JSON_TYPE_INTEGER || nInstanceType == JSON_TYPE_FLOAT)
            {
                /// @note We're using a query here in case we run into numbers larger than
                ///     the signed 32-bit maximum.  This should handle up to sqlite's maximum
                ///     integer/float size (64-bit).
                string s = r"
                    SELECT (CAST(val AS INTEGER) == val)
                    FROM (SELECT json_extract(:instance, '$') AS val);
                ";
                sqlquery q = schema_core_PrepareModuleQuery(s);
                SqlBindJson(q, ":instance", jInstance);

                if (SqlStep(q) ? SqlGetInt(q, 0) : FALSE)
                {
                    schema_debug_ExitFunction(__FUNCTION__, "instance type is integer");
                    schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
                    return joOutputUnit;
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
                schema_debug_ExitFunction(__FUNCTION__, "instance type found in type array");
                schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
                return joOutputUnit;
            }
        }
    }
    else if (nTypeType == JSON_TYPE_ARRAY)
    {
        int i; for (; i < JsonGetLength(jSchema); i++)
        {
            json joValidate = schema_validate_Type(jInstance, JsonArrayGet(jSchema, i));
            if (schema_output_GetValid(joValidate))
                schema_output_InsertAnnotation(joOutputUnit, joValidate, sSource + " (array)");
        }
    }

    json jaAnnotations = JsonObjectGet(joOutputUnit, "annotations");
    if (JsonGetType(jaAnnotations) == JSON_TYPE_NULL || JsonGetLength(jaAnnotations) == 0)
        schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    else if (nTypeType == JSON_TYPE_ARRAY && JsonGetLength(jaAnnotations) > 0)
        schema_output_SetAnnotation(schema_output_GetOutputUnit(), sKeyword, jSchema, sSource);
    
    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @private Validate the related keywords `enum` and `const`.
json schema_validate_Enum(json jInstance, json jSchema, string sKeyword)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "jInstance", jInstance);
    schema_debug_Argument(__FUNCTION__, "jSchema", jSchema);

    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    /// @brief `const`. The value of `const` may be of any type, including null.  Successful validation occurs if the
    ///     instance is equal to the schema.

    if (sKeyword == "const")
        jSchema = JsonArrayInsert(JsonArray(), jSchema);

    /// @brief `enum`. The value of `enum` must be an array.  Successful validation occurs if the instance is equal to
    ///     at least one item in the array.

    if (JsonGetType(JsonFind(jSchema, jInstance)) != JSON_TYPE_NULL)
    {
        schema_debug_ExitFunction(__FUNCTION__, "instance type not found in schema");
        return joOutputUnit;
    }

    /// @note Non-ascii characters run into encoding issues when parsed into json
    ///     strings and are usually represented by escaped unicode representations,
    ///     sometimes being mangled/mojibaked.  This query should un-mangle the
    ///     unicode values into the original characters.
    if (JsonGetType(jInstance) == JSON_TYPE_STRING)
    {
        string s = r"
            SELECT 1
            FROM json_each(:schema)
            WHERE
                CAST(CAST(value AS BLOB) AS TEXT) =
                CAST(CAST(json_extract(json(:instance), '$') AS BLOB) AS TEXT);
        ";
        sqlquery q = schema_core_PrepareModuleQuery(s);
        SqlBindJson(q, ":schema", jSchema);
        SqlBindJson(q, ":instance", jInstance);

        if (SqlStep(q))
        {
            schema_debug_ExitFunction(__FUNCTION__, "instance type found in schema");
            return joOutputUnit;
        }
    }

    schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @private `pattern`.  The value of `pattern` must be a string an and is expected to be
///     a valid ecma-262 regext string.  Successful validation occurs if the regular
///     expression matches the instance string.
json schema_validate_Pattern(json jsInstance, json jSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json joOutputUnit = schema_output_GetOutputUnit();
    
    string sSource = __FUNCTION__;
    string sKeyword = "pattern";

    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
    {
        schema_debug_ExitFunction(__FUNCTION__, "instance type is not string");
        return joOutputUnit;
    }

    if (!schema_validate_RegExpMatch(JsonGetString(jSchema), JsonGetString(jsInstance)))
        schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @todo
///     [ ] This whole function
////    [ ] error reporting strings above.  Use them or get rid of them.

/// @brief Validates the string "format" keyword.
/// @param jsInstance The instance to validate.
/// @param jSchema The schema value for "format".
/// @returns An output object containing the validation result.
json schema_validate_Format(json jsInstance, json jSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json joOutputUnit = schema_output_GetOutputUnit();

    if (JsonGetType(jsInstance) != JSON_TYPE_STRING)
    {
        schema_debug_ExitFunction(__FUNCTION__, "instance type is not string");
        return joOutputUnit;
    }

    string sInstance = JsonGetString(jsInstance);
    string sFormat = JsonGetString(jSchema);
    int bValid = FALSE;

    if (sFormat == "email")    
    {
        bValid = schema_validate_RegExpMatch("^[a-zA-Z0-9!#$%&'*+\\-/=?^_`{|}~]+(?:\\.[a-zA-Z0-9!#$%&'*+\\-/=?^_`{|}~]+)*@(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$", sInstance);
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
        sqlquery q = schema_core_PrepareModuleQuery(s);
        SqlBindString(q, ":data", sInstance);

        bValid = SqlStep(q) ? SqlGetInt(q, 0) : FALSE;
    }
    else if (sFormat == "ipv4")
    {
        bValid = schema_validate_RegExpMatch("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\."
                           + "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", sInstance);
    }
    else if (sFormat == "ipv6")
    {
        bValid = schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}$", sInstance)
              || schema_validate_RegExpMatch("^::([0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4}$", sInstance)
              || schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){1,7}:$", sInstance)
              || schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){1}(:[0-9A-Fa-f]{1,4}){1,6}$", sInstance)
              || schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){2}(:[0-9A-Fa-f]{1,4}){1,5}$", sInstance)
              || schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){3}(:[0-9A-Fa-f]{1,4}){1,4}$", sInstance)
              || schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){4}(:[0-9A-Fa-f]{1,4}){1,3}$", sInstance)
              || schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){5}(:[0-9A-Fa-f]{1,4}){1,2}$", sInstance)
              || schema_validate_RegExpMatch("^([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}){1}$", sInstance);
    }
    else if (sFormat == "uri")
    {
        bValid = schema_validate_RegExpMatch("^[a-zA-Z][a-zA-Z0-9+.-]*:[^\\s]*$", sInstance);
    }
    else if (sFormat == "uri-reference")
    {
        bValid = (sInstance == "") || schema_validate_RegExpMatch("^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?$", sInstance);
    }
    else if (sFormat == "iri")
    {
        bValid = schema_validate_RegExpMatch("^[\\w\\d\\-._~:/?#\\[\\]@!$&'()*+,;=%]+$", sInstance);
    }
    else if (sFormat == "iri-reference")
    {
        bValid = (sInstance == "")
              || schema_validate_RegExpMatch("^[\\w\\d\\-._~:/?#\\[\\]@!$&'()*+,;=%]+$", sInstance)
              || schema_validate_RegExpMatch("^[/?#]", sInstance);
    }
    else if (sFormat == "date")
    {
        bValid = schema_validate_RegExpMatch("^\\d{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))$", sInstance);
    }
    else if (sFormat == "date-time")
    {
        bValid = schema_validate_RegExpMatch("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$", sInstance);
    }
    else if (sFormat == "time")
    {
        bValid = schema_validate_RegExpMatch("^\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})?$", sInstance);
    }
    else if (sFormat == "duration")
    {
        bValid = schema_validate_RegExpMatch("^P(?!$)(\\d+Y)?(\\d+M)?(\\d+D)?(T(?!$)(\\d+H)?(\\d+M)?(\\d+(\\.\\d+)?S)?)?$", sInstance);
    }
    else if (sFormat == "json-pointer")
    {
        bValid = (sInstance == "") || schema_validate_RegExpMatch("^(/([^/~]|~[01])*)*$", sInstance);
    }
    else if (sFormat == "relative-json-pointer")
    {
        bValid = schema_validate_RegExpMatch("^(0|[1-9][0-9]*)(#|(/([^/~]|~[01])*)*)$", sInstance);
    }
    else if (sFormat == "uuid")
    {
        bValid = schema_validate_RegExpMatch("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", sInstance);
    }
    else if (sFormat == "regex")
    {
        bValid = (GetStringLength(sInstance) > 0);
        
        if (bValid)
        {
            bValid = schema_validate_RegExpMatch("^[^\\\\]*(\\\\.[^\\\\]*)*$", sInstance);
        }
    }
    else
    {
        schema_output_SetError(joOutputUnit, "unsupported format: " + sFormat);
        return joOutputUnit;
    }

    if (bValid)
        schema_output_SetAnnotation(joOutputUnit, "format", jSchema);
    else
    {
        schema_output_SetValid(joOutputUnit, FALSE);
        schema_output_SetError(joOutputUnit, "instance does not match format: " + sFormat);
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @private Convert and instance into an equivalent numerical value for use in an assertion.
/// @note:
///     - float and integer instances will be returned without change.
///     - string instances will return the length of the string.
///     - array instances will return the length of the array.
///     - object instances will return the number of keys in the object.
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

/// @private Conduct an assertion.  This function is called by most of the assertion keywords
///     to conduct a basic numerical comparison.
/// @note The `multipleOf` comparison uses a modulo operation.  An sqlite query is employed
///     to allow the use of exremely large or extremely small numbers without losing precision.
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
    sqlquery q = schema_core_PrepareModuleQuery(s);
    SqlBindJson(q, ":instance", schema_validate_ConvertNumericValue(jInstance));
    SqlBindJson(q, ":schema", jSchema);
    SqlBindString(q, ":op", sOperator);

    if ((SqlStep(q) ? SqlGetInt(q, 0) : FALSE) == FALSE)
        schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), __FUNCTION__ + " (" + sKeyword + ")");

    return joOutputUnit;
}

/// @private `uniqueItems`.  The value of `uniqueItems` must be boolean.  Successful validation occurs when either
///     uniqueItems = false, or unqiueItems = true and all items in the instance array are unique.
json schema_validate_UniqueItems(json jaInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "uniqueItems";

    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
        return joOutputUnit;

    if (jSchema == JSON_FALSE)
        schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource + " (false)");
    else
    {
        if (JsonGetLength(jaInstance) == JsonGetLength(JsonArrayTransform(jaInstance, JSON_ARRAY_UNIQUE)))
            schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
        else
            schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    }

    return joOutputUnit;
}

/// @private Tuple validation function for `prefixItems` and `items` (array).
/// @see schema_validate_Items() below.
json schema_validate_Tuple(json jaInstance, json jSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);

    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    int bAnnotate = schema_keyword_Annotate();

    int nSchemaLength = JsonGetLength(jSchema);
    if (nSchemaLength > 0)
    {
        json jaEvaluatedItems = JsonArray();
        int i; for (; i < nSchemaLength && i < JsonGetLength(jaInstance); i++)
        {
            schema_scope_PushSchemaPath(IntToString(i));
            schema_scope_PushInstancePath(IntToString(i));

            json joResult = schema_core_Validate(JsonArrayGet(jaInstance, i), JsonArrayGet(jSchema, i));
            schema_output_InsertResult(joOutputUnit, joResult, sSource);
            jaEvaluatedItems = JsonArrayInsert(jaEvaluatedItems, JsonInt(i));

            schema_scope_PopInstancePath();
            schema_scope_PopSchemaPath();
        }

        if (bAnnotate)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems, sSource);
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @private Uniform validation function for `items` (schema) and `additionalItems`.
/// @see schema_validate_Items() below.
json schema_validate_Uniform(json jaInstance, json jSchema, int nTupleLength)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json joOutputUnit = schema_output_GetOutputUnit();

    int bAnnotate = schema_keyword_Annotate();

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
                    schema_output_InsertAnnotation(joOutputUnit, joItemOutputUnit, sSource);
                else
                    schema_output_InsertError(joOutputUnit, joItemOutputUnit, sSource);

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
                schema_output_InsertResult(joOutputUnit, joResult, sSource);

                if (bAnnotate)
                    jaEvaluatedItems = JsonArrayInsert(jaEvaluatedItems, JsonInt(i));

                schema_scope_PopInstancePath();
            }
        }

        if (bAnnotate)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems, sSource);
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @private Validate the interdependent keywords `prefixItems`, `items` and `additionalItems`.
json schema_validate_Items(json jInstance, json jaPrefixItems, json jItems, json jAdditionalItems)
{    
    schema_debug_EnterFunction(__FUNCTION__);

    json jaOutput = JsonArray();

    if (JsonGetType(jInstance) != JSON_TYPE_ARRAY)
    {
        schema_debug_ExitFunction(__FUNCTION__, "instance type is not array");
        return jaOutput;
    }

    /// @brief `prefixItems`.  The value of this keyword must be a non-empty array of valid schema.  `prefixItems`
    ///     is a tuple validation, comparing each item in the instance array against the corresponding schema
    ///     item from the `prefixItems` array.
    /// @note If prefixItems.length > instance.length, excess prefixItem schema are ignored.
    /// @note If prefixItems.length < instance.length, excess instance items are not evaluated by `prefixItems`.

    string sKeyword = "prefixItems";
    if (JsonGetType(jaPrefixItems) == JSON_TYPE_ARRAY && schema_keyword_IsActive(sKeyword))
    {
        schema_scope_PushSchemaPath(sKeyword);
        json joResult = schema_validate_Tuple(jInstance, jaPrefixItems);
        JsonArrayInsertInplace(jaOutput, joResult);
        schema_scope_PopSchemaPath();
    }

    /// @brief `items`.  When the value of this keyword is an array, `items` is a tuple validation, comparing each
    ///     item in the instance array against the corresponding schema item in the `items` array.
    /// @note If items.length > instance.length, excess `items` schema are ignored.
    /// @note If items.length < instance.length, excess instance items are not evaluated by `items`.

    /// @brief `items`.  When the value of this keyword is a schema, `items` is a uniform validation.  Validation
    ///     only occurs against instance items that have not been previously evaluated by `prefixItems`.  For all
    ///     remaining unevaluated instance items, each instance item is validated against the `items` schema.
    /// @note If prefixItems.length > instance.length, `items` schema is ignored.

    sKeyword = "items";
    int nItemsType = JsonGetType(jItems);
    if (nItemsType != JSON_TYPE_NULL && schema_keyword_IsActive(sKeyword))
    {
        schema_scope_PushSchemaPath(sKeyword);
        
        json joResult;
        if (nItemsType == JSON_TYPE_ARRAY)
        {
            joResult = schema_validate_Tuple(jInstance, jItems);
        }
        else if (nItemsType == JSON_TYPE_OBJECT || nItemsType == JSON_TYPE_BOOL)
        {
            int nTupleLength = 0;
            if (JsonGetType(jaPrefixItems) == JSON_TYPE_ARRAY)
                nTupleLength = JsonGetLength(jaPrefixItems);

            joResult = schema_validate_Uniform(jInstance, jItems, nTupleLength);
        }

        JsonArrayInsertInplace(jaOutput, joResult);
        schema_scope_PopSchemaPath();
    }

    /// @brief `additionalItems`.  The value of `additionalItems` must be a valid schema.  Validation
    ///     only occurs against instance items that have not been previously evaluated by `items` (array).
    ///     For all remaining unevaluated instance items, each instance item is validated against the
    ///     `additionalItems` schema.
    /// @note If additionalItems = true, all unevaluated instance items are validated.
    /// @note If additionalItems = false, validation of unevaluated items is disallowed and the instace
    ///     fails validation.
    /// @note additionalItems = {} is functionally identical to additionalItems = true.

    sKeyword = "additionalItems";
    int nAdditionalItemsType = JsonGetType(jAdditionalItems);
    if (nAdditionalItemsType != JSON_TYPE_NULL && schema_keyword_IsActive(sKeyword))
    {
        if (JsonGetType(jItems) == JSON_TYPE_ARRAY)
        {
            schema_scope_PushSchemaPath(sKeyword);

            int nTupleLength = JsonGetLength(jItems);
            json joResult = schema_validate_Uniform(jInstance, jAdditionalItems, nTupleLength);

            JsonArrayInsertInplace(jaOutput, joResult);
            schema_scope_PopSchemaPath();
        }
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return jaOutput;
}

/// @private Validate the interdependent keywords `contains`, `minContains` and `maxContains`.
json schema_validate_Contains(json jaInstance, json jContains, json jiMinContains, json jiMaxContains)
{
    schema_debug_EnterFunction(__FUNCTION__);
    json jaOutput = JsonArray();
    string sSource = __FUNCTION__;

    if (JsonGetType(jaInstance) != JSON_TYPE_ARRAY)
    {
        schema_debug_ExitFunction(__FUNCTION__, "instance type is not array");
        return jaOutput;
    }

    /// @note in the rare case that a user provides a schema that contains a `minContains`
    ///     and/or `maxContains`, but no `contains` key, all keywords should be ignored.
    if (JsonGetType(jContains) == JSON_TYPE_NULL)
    {
        schema_debug_ExitFunction(__FUNCTION__, "`contains` schema is null");
        return jaOutput;
    }

    /// @note `contains` is valid in earlier drafts of metaschema, but `minContains` and
    ///     `maxContains` were not introduced until much later.  If working with an earlier
    ///     draft and `minContains` or `maxContains` are present, they should be ignored.
    if (!schema_keyword_IsActive("minContains"))
    {
        schema_debug_Message("`minContains` schema provided; invalid in this context");
        jiMinContains = JsonNull();
    }

    if (!schema_keyword_IsActive("maxContains"))
    {
        schema_debug_Message("`maxContains` schema provided; invalid in this context");
        jiMaxContains = JsonNull();
    }

    int bAnnotate = schema_keyword_Annotate();

    /// @brief `contains`.  The value of `contains` must be a valid schema.  Validation occurs
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
        
        if (jContains == JsonObject())
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
                    schema_output_InsertAnnotation(joOutputUnit, joItemOutputUnit, sSource + "[BOOL]");
                else
                    schema_output_InsertError(joOutputUnit, joItemOutputUnit, sSource + "[BOOL]");

                schema_scope_PopInstancePath();
            }

            schema_output_SetValid(joOutputUnit, bContains);
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
                schema_output_InsertAnnotation(joOutputUnit, joResult, sSource + "[OBJECT/Inner]");
                schema_scope_PopInstancePath();
            }

            int nMatches = JsonGetLength(jaEvaluatedItems);
            if (
                (nMatches < (nMinContains == -1 ? 1 : nMinContains)) ||
                (nMaxContains != -1 && nMatches > nMaxContains)
            )
            {
                schema_output_SetValid(joOutputUnit, FALSE);
            }
        }

        if (bAnnotate)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems, sSource + "[OBJECT/outer]");

        schema_scope_PopSchemaPath();
        JsonArrayInsertInplace(jaOutput, joOutputUnit);

        /// @brief `minContains`.  The value of `minContains` must be a non-negative integer.  This
        ///     keyword is ignored if `contains` is not present in the same schema object.  To
        ///     validate against `minContains`, the instance array must have at least `minContains`
        ///     items that are valid against the `contains` schema.
        /// @note If minContains = 0, the instance array is considered valid against the `contains`
        ///     schema, even if no instance items can be validated against the `contains` schema or
        ///     if the instance array is empty.
        /// @note If `minContains` is ommitted, a default value of 1 is used.

        /// @brief `maxContains`.  The value of `maxContains` must be a non-negative integer.  This
        ///     keyword is ignored if `contains` is not present in the same schema object.  To
        ///     validate against `maxContains`, the instance array must have no more than `maxContains`
        ///     items that are valid against the `contains` schema.
        /// @note If maxContains = 0 && instance.length = 0, the instance is considered valid against
        ///     the `contains` schema.

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
                schema_validate_Assertion(sKeyword, JsonInt(JsonGetLength(jaEvaluatedItems)), sOperator, jKeyword);
                schema_scope_PopSchemaPath();

                JsonArrayInsertInplace(jaOutput, joOutputUnit);
            }
        }
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return jaOutput;
}

/// @private `required`.  The value of `required` must be an array and its items must be of type string
///     and must be unique.  Successful validation occurs if every item i the array is the name of a
///     property in the instance.
json schema_validate_Required(json joInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;
    string sKeyword = "required";

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
        return joOutputUnit;

    json jaMissingProperties = JsonArray();
    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        json jProperty = JsonArrayGet(jSchema, i);
        if (!schema_validate_HasKey(joInstance, JsonGetString(jProperty)))
            jaMissingProperties = JsonArrayInsert(jaMissingProperties, jProperty);
    }

    if (JsonGetLength(jaMissingProperties) > 0)
        schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
    else
        schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);

    return joOutputUnit;
}

/// @private `dependentRequired`.  The value of `dependentRequired` must be an object and any properties
///     within the object must be arrays.  Any items within these arrays must be of type string and must
///     be unique.  Successful validation occurs if, for each property name that appears in both the
///     instance and the schema, every item in the corresponding array is also the name of a property
///     in the instance.
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
        if (schema_validate_HasKey(joInstance, JsonGetString(jProperty)))
        {
            json jaRequired = JsonObjectGet(jSchema, JsonGetString(jProperty));
            json jaMissing = JsonArray();
            
            int j; for (; j < JsonGetLength(jaRequired); j++)
            {
                json jRequiredKey = JsonArrayGet(jaRequired, j);
                // Check if the required dependency exists in the instance (robustly)
                if (!schema_validate_HasKey(joInstance, JsonGetString(jRequiredKey)))
                    JsonArrayInsertInplace(jaMissing, jRequiredKey);
            }

            if (JsonGetLength(jaMissing) > 0)
                schema_output_SetError(joOutputUnit, "Dependency failed: " + JsonGetString(jProperty) + " requires " + JsonDump(jaMissing), sSource);
        }
    }

    return joOutputUnit;
}

/// @private `propertyNames`.  The value of `propertyNames` must be a valid schema.  Successful
///     validation occurs if every property name in the instance validates against the provided
///     schema.
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
            schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource);
        else
            schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
    }
    else if (nKeywordType == JSON_TYPE_OBJECT)
    {
        if (joInstance == JsonObject())
            schema_output_SetAnnotation(joOutputUnit, sKeyword, jSchema, sSource);
        else
        {
            int i; for (; i < nInstanceKeys; i++)
            {
                string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                schema_scope_PushInstancePath(sInstanceKey);

                json joResult = schema_core_Validate(JsonString(sInstanceKey), jSchema);
                schema_output_InsertResult(joOutputUnit, joResult, sSource);

                schema_scope_PopInstancePath();
            }
        }
    }

    return joOutputUnit;
}

/// @private Validates interdependent object keywords "properties", "patternProperties",
///     "additionalProperties", "dependencies", "dependentSchemas".
json schema_validate_Object(
    json joInstance,
    json joProperties,
    json joPatternProperties,
    json jAdditionalProperties,
    json joDependencies,
    json joDependentSchemas
)
{
    schema_debug_EnterFunction(__FUNCTION__);

    json jaOutput = JsonArray();
    string sFunction = __FUNCTION__;
    string sSource = sFunction;

    int bAnnotate = schema_keyword_Annotate();

    if (JsonGetType(joInstance) != JSON_TYPE_OBJECT)
    {
        schema_debug_ExitFunction(__FUNCTION__, "instance is not a json object");
        return jaOutput;
    }

    /// @note Since various `property`-related keywords are order-of-evaluation dependent, but
    ///     otherwise independent, null out any keywords that are not valid in the current
    ///     context.  Type checking is this function automatically ignores null types.
    /// @todo is this any better than using && schema_keyword_IsActive in each section below?
    ////        If so, standardize across functions.  Also, if we wipe out all-available keyword
    ///         here, it'll return an empty array, which I think is fine (?)
    // if (!schema_keyword_IsActive("properties")) joProperties = JsonNull();
    // if (!schema_keyword_IsActive("patternProperties")) joPatternProperties = JsonNull();
    // if (!schema_keyword_IsActive("additionalProperties")) jAdditionalProperties = JsonNull();
    // if (!schema_keyword_IsActive("dependencies")) joDependencies = JsonNull();
    // if (!schema_keyword_IsActive("dependentSchemas")) joDependentSchemas = JsonNull();

    json jaInstanceKeys = JsonObjectKeys(joInstance);
    int nInstanceKeys = JsonGetLength(jaInstanceKeys);

    /// @brief `properties`.  The schema value of `properties` must be an object and all values within
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
            schema_output_SetAnnotation(joOutputUnit, sKeyword, joProperties, sSource);
        else
        {
            json jaPropertyKeys = JsonObjectKeys(joProperties);
            json jaEvaluatedProperties = JsonArray();

            int i; for (; i < nInstanceKeys; i++)
            {
                string sInstanceKey = JsonGetString(JsonArrayGet(jaInstanceKeys, i));
                schema_scope_PushInstancePath(sInstanceKey);

                json joPropertySchema = schema_validate_JsonObjectGet(joProperties, sInstanceKey);
                if (JsonGetType(joPropertySchema) != JSON_TYPE_NULL)
                {
                    schema_scope_PushSchemaPath(sInstanceKey);

                    json joResult = schema_core_Validate(schema_validate_JsonObjectGet(joInstance, sInstanceKey), joPropertySchema);
                    schema_output_InsertResult(joOutputUnit, joResult, sSource);                

                    if (bAnnotate)
                        JsonArrayInsertInplace(jaEvaluatedProperties, JsonString(sInstanceKey));
                    
                    schema_scope_PopSchemaPath();
                }
                
                schema_scope_PopInstancePath();
            }

            if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
                schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties, sSource);
        }
        
        JsonArrayInsertInplace(jaOutput, joOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief `patternProperties`.  The schema value of `patternProperties` must be an object.  The schema
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
            schema_output_SetAnnotation(joOutputUnit, sKeyword, joPatternProperties, sSource);
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

                    if (schema_validate_RegExpMatch(sPattern, sInstanceKey))
                    {
                        json joPatternSchema = schema_validate_JsonObjectGet(joPatternProperties, sPattern);
                        if (JsonGetType(joPatternSchema) != JSON_TYPE_NULL)
                        {
                            json joResult = schema_core_Validate(schema_validate_JsonObjectGet(joInstance, sInstanceKey), joPatternSchema);
                            schema_output_InsertResult(joOutputUnit, joResult, sSource);

                            if (bAnnotate)
                                JsonArrayInsertInplace(jaEvaluatedProperties, JsonString(sInstanceKey));
                        }
                    }

                    schema_scope_PopSchemaPath();
                }

                schema_scope_PopInstancePath();
            }

            if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
                schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties);
        }

        JsonArrayInsertInplace(jaOutput, joOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief `additionalProperties`. The value of `additionalProperties` must be a valid schema.  Validation only
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
                schema_output_SetError(joOutputUnit, schema_output_GetErrorMessage(sKeyword), sSource + "[additionalProperties]");
            else if (jAdditionalProperties == JSON_TRUE)
                schema_output_SetAnnotation(joOutputUnit, sKeyword, jAdditionalProperties, sSource);

            if (bAnnotate && jAdditionalProperties == JSON_TRUE)
                jaEvaluatedProperties = jaUnevaluatedProperties;
        }
        else if (nKeywordType == JSON_TYPE_OBJECT)
        {
            int i; for (; i < JsonGetLength(jaUnevaluatedProperties); i++)
            {
                string sUnevaluatedKey = JsonGetString(JsonArrayGet(jaUnevaluatedProperties, i));
                schema_scope_PushInstancePath(sUnevaluatedKey);

                json joInstanceChild = schema_validate_JsonObjectGet(joInstance, sUnevaluatedKey);
                if (JsonGetType(joInstanceChild) != JSON_TYPE_NULL)
                {
                    json joResult = schema_core_Validate(joInstanceChild, jAdditionalProperties);
                    schema_output_InsertResult(joOutputUnit, joResult, sSource);

                    if (bAnnotate)
                        JsonArrayInsertInplace(jaEvaluatedProperties, JsonString(sUnevaluatedKey));
                }

                schema_scope_PopInstancePath();
            }
        }
        
        if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
            schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties, sSource);

        JsonArrayInsertInplace(jaOutput, joOutputUnit);
        schema_scope_PopSchemaPath();
    }

    /// @brief `dependentSchemas`.  The value of `dependentSchemas` must be an object.  Each value in the object
    ///     must be a valid schema.  If an object key is a property name in the instance, successful validation
    ///     occurs if the entire instance validates against the matching schema.

    /// @brief `dependencies`.  This keyword is the previous iteration of the `dependentSchemas` keyword above.
    ///     The evaluation requirements and methodology are the same.  `dependentSchemas` is the new keyword name
    ///     for use in more modern schema, however, `dependencies` is still a valid keyword in most version of
    ///     official metaschema.

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

                if (schema_validate_HasKey(joInstance, sSchemaKey))
                {
                    json joSchema = JsonObjectGet(jSchema, sSchemaKey);
                    int nSchemaType = JsonGetType(joSchema);
                    if (nSchemaType == JSON_TYPE_BOOL)
                    {
                        if (joSchema == JSON_TRUE)
                        {
                            json joOutput = schema_output_GetOutputUnit();
                            schema_output_SetAnnotation(joOutput, sSchemaKey, joSchema, sSource);
                            schema_output_InsertAnnotation(joOutputUnit, joOutput);
                        }
                        else
                        {
                            json joOutput = schema_output_GetOutputUnit();
                            schema_output_SetError(joOutput, sSchemaKey + " not allowed", sSource);
                            schema_output_InsertError(joOutputUnit, joOutput);
                        }
                    }
                    else
                    {
                        json joResult;
                        if (nSchemaType == JSON_TYPE_ARRAY)
                            joResult = schema_validate_DependentRequired(joInstance, joSchema);
                        else if (nSchemaType == JSON_TYPE_OBJECT)
                            joResult = schema_core_Validate(joInstance, joSchema);
                
                        schema_output_InsertResult(joOutputUnit, joResult, sSource);

                        if (bAnnotate && schema_output_GetValid(joResult))
                        {
                            jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(joResult));
                            // dependentSchemas only applies to objects, so we don't need to check for evaluatedItems
                            // unless the subschema somehow evaluated items on the object instance (which is impossible)
                        }
                    }
                }

                schema_scope_PopSchemaPath();
            }
            
            if (bAnnotate && JsonGetLength(jaEvaluatedProperties) > 0)
                schema_output_SetAnnotation(joOutputUnit, sAnnotationKey, jaEvaluatedProperties, sSource);

            JsonArrayInsertInplace(jaOutput, joOutputUnit);
        }
        
        schema_scope_PopSchemaPath();
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return jaOutput;
}

void schema_validate_Unevaluated(json jInstance, json joSchema, json joOutputUnit)
{
    /// @brief `unevaluatedItems`.  The value of `unevaluatedItems` must be a valid schema.  Validation
    ///     only occurs against instance items that have not been previously evaluated by `prefixItems`,
    ///     `items` or `contains`.  For all remaining unevaluated instance items, each instance item is
    ///     validated against the `unevaluatedItems` schema.
    /// @note if unevaluatedItems = true, all unevaluated instance items are validated.
    /// @note if unevaluatedItems = false, validation of unevaluated items is disallowed and the instance
    ///     fails validation if there are any unevaluated items remaining.
    /// @note unevaluatedItems = {} is functionally identical to unevaluatedItems = true.

    /// @brief `unevaluatedProperties`.  The value of `unevaluatedProperties` must be a valid schema.
    ///     Validation only occurs against instance properties that have not been previously evaluated
    ///     by `properties`, `patternProperties` or `additionalProperties`.  For all remaining properties,
    ///     each instance is validated agains the `unevaluatedProperties` schema.
    /// @note if unevalautedProperties = true, all unevaluated instance properties are validated.
    /// @note if unevaluatedProperties = false, validation of unevaluated items is disallowed and the
    ///     instance fails validation if there are any unevaluated properties remaining.
    /// @note unevaluatedProperties = {} is functionally identical to unevaluatedProperties = true.

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
                schema_output_SetAnnotation(joOutput, sAnnotationKey, jaUnevaluatedKeys, sSource);
                if (nKeywordType == JSON_TYPE_BOOL)
                {
                    schema_output_SetAnnotation(joOutput, sKeyword, jKeywordSchema);

                    if (jKeywordSchema == JSON_FALSE)
                        schema_output_SetError(joOutput, sAnnotationKey + " disallowed", sSource);
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
                                jChild = schema_validate_JsonObjectGet(jInstance, sUnevaluatedKey);

                            json joResult = schema_core_Validate(jChild, jKeywordSchema);
                            schema_output_InsertResult(joOutput, joResult, sSource);

                            schema_scope_PopInstancePath();
                        }
                    }
                }
            }

            schema_output_InsertResult(joOutputUnit, joOutput, sSource);
            schema_scope_PopSchemaPath();
        }
    }
}

/// @private `not`.  The value of `not` must be a valid schema.  Successful validation occurs if the
///     instance fails to validate succesfully against the provided schema.
json schema_validate_Not(json jInstance, json jSchema)
{
    json joResult = schema_core_Validate(jInstance, jSchema);
    schema_output_SetValid(joResult, !schema_output_GetValid(joResult));
    return joResult;
}

/// @private `allOf`.  The valud of `allOf` must be a non-empty array.  Each item in the array must be
///     a valid schema.  Successful validation occurs if the instance validates successfully against
///     all schemas within the array.
json schema_validate_AllOf(json jInstance, json jSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);

    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    int bAnnotate = schema_keyword_Annotate();

    json jaEvaluatedProperties = JsonArray();
    json jaEvaluatedItems = JsonArray();

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        if (schema_output_GetValid(joResult))
        {
            if (bAnnotate)
            {
                jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(joResult));
                jaEvaluatedItems = schema_scope_MergeArrays(jaEvaluatedItems, schema_output_GetEvaluatedItems(joResult));
            }
        }

        schema_output_InsertResult(joOutputUnit, joResult, sSource);
        schema_scope_PopSchemaPath();
    }

    if (bAnnotate && schema_output_GetValid(joOutputUnit))
    {
        if (JsonGetLength(jaEvaluatedProperties) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", jaEvaluatedProperties);

        if (JsonGetLength(jaEvaluatedItems) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems);
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// @private `anyOf`.  The value of `anyOf` must be a non-empty array.  Each item in the array must be a
///     valid schema.  Successful validation occurs if the instance validates successfully against at least
///     of the schema in the array.
json schema_validate_AnyOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaResults = JsonArray();

    string sSource = __FUNCTION__;

    int bAnnotate = schema_keyword_Annotate();

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        JsonArrayInsertInplace(jaResults, joResult);

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

            schema_output_InsertAnnotation(joOutputUnit, joResult, sSource);
        }
        else
            schema_output_InsertError(joOutputUnit, JsonArrayGet(jaResults, i), sSource);
    }

    if (bAnnotate)
    {
        if (JsonGetLength(jaEvaluatedProperties) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", jaEvaluatedProperties);

        if (JsonGetLength(jaEvaluatedItems) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems);
    }

    schema_output_SetValid(joOutputUnit, JsonGetLength(JsonObjectGet(joOutputUnit, "annotations")) > 0);
    return joOutputUnit;
}

/// @private `oneOf`.  The value of `oneOf` must be a non-empty array.  Each item in the array must be a
///     valid schema.  Successful validation occurs if the instance validates successfully against exactly
///     one schema in the array.
json schema_validate_OneOf(json jInstance, json jSchema)
{
    json joOutputUnit = schema_output_GetOutputUnit();
    json jaResults = JsonArray();
    string sSource = __FUNCTION__;

    int bAnnotate = schema_keyword_Annotate();

    int i; for (; i < JsonGetLength(jSchema); i++)
    {
        schema_scope_PushSchemaPath(IntToString(i));

        json joResult = schema_core_Validate(jInstance, JsonArrayGet(jSchema, i));
        schema_output_InsertResult(joOutputUnit, joResult, sSource);
        
        if (schema_output_GetValid(joResult))
            JsonArrayInsertInplace(jaResults, joResult);

        schema_scope_PopSchemaPath();
    }

    if (JsonGetLength(jaResults) == 1)
    {
        json joResult = JsonArrayGet(jaResults, 0);

        if (bAnnotate)
        {
            json jaEvaluatedKeys = schema_output_GetEvaluatedProperties(joResult);
            if (JsonGetLength(jaEvaluatedKeys) > 0)
                schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", schema_output_GetEvaluatedProperties(joResult));
            
            jaEvaluatedKeys = schema_output_GetEvaluatedItems(joResult);
            if (JsonGetLength(jaEvaluatedKeys) > 0)
                schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", schema_output_GetEvaluatedItems(joResult));
        }
    }

    schema_output_SetValid(joOutputUnit, JsonGetLength(jaResults) == 1);
    return joOutputUnit;
}

/// @private Validates interdependent applicator keywords "if", "then", "else".
json schema_validate_Conditional(json jInstance, json joIf, json joThen, json joElse)
{
    schema_debug_EnterFunction(__FUNCTION__);

    json joOutputUnit = schema_output_GetOutputUnit();
    string sSource = __FUNCTION__;

    int bAnnotate = schema_keyword_Annotate();

    if (JsonGetType(joIf) == JSON_TYPE_NULL)
    {
        schema_debug_ExitFunction(__FUNCTION__, "joIf is null");
        return JsonNull();
    }

    if (joIf == JsonObject())
        joIf = JSON_TRUE;

    /// @brief `if`.  The valud of `if` must be a valid schema.  Successful validation of the instance
    ///     against the `if` schema does not affect the overall validity of the validation process for
    ///     the instance.  Validation results are used only to determine whether to proceed to the `then`
    ///     keyword schema or the `else` keyword schema, if provided.  Successful validation occurs when
    ///     instances that successfully validate against the `if` schema also validate successfully against
    ///     the `then` schema, or instances that fail to validate against the `if` schema successfully
    ///     validate against the `else` schema.

    string sKeyword = "if";
    schema_scope_PushSchemaPath(sKeyword);

    json jaEvaluatedProperties = JsonArray();
    json jaEvaluatedItems = JsonArray();

    int bIf, nKeywordType = JsonGetType(joIf);
    if (nKeywordType == JSON_TYPE_BOOL)
    {
        schema_output_InsertAnnotation(joOutputUnit, schema_output_GetOutputUnit());
        bIf = JsonGetInt(joIf);
    }
    else if (nKeywordType == JSON_TYPE_OBJECT)
    {
        json joResult = schema_core_Validate(jInstance, joIf);
        schema_output_InsertAnnotation(joOutputUnit, joResult, sSource);

        bIf = schema_output_GetValid(joResult);

        if (bAnnotate && bIf)
        {
            jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(joResult));
            jaEvaluatedItems = schema_scope_MergeArrays(jaEvaluatedItems, schema_output_GetEvaluatedItems(joResult));
        }
    }

    schema_scope_PopSchemaPath();

    /// @brief `then`.  The value of `then` must be a valid schema.  Successful validation occurs when the `if`
    ///     schema is present, the instance successfully validates against the `if` schema and the `then` schema.
    /// @note If the `if` schema is absent, the `then` schema is ignored.

    /// @brief `else`.  The value of `else` must be a valid schema.  Successful validation occurs when the `if`
    ///     schema is present, the instance fails to validate against the `if` schema and successfully validates
    ///     against the `else` schema.
    /// @note If the `if` schema is absent, the `else` schema is ignored.

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
            schema_output_InsertAnnotation(joOutputUnit, joOutput);
        else if (jSchema == JSON_FALSE)
            schema_output_InsertError(joOutputUnit, joOutput);
    }
    else if (nSchemaType == JSON_TYPE_OBJECT)
    {
        json joResult = schema_core_Validate(jInstance, jSchema);
        schema_output_InsertResult(joOutputUnit, joResult, sSource);

        if (bAnnotate && schema_output_GetValid(joResult))
        {
            jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(joResult));
            jaEvaluatedItems = schema_scope_MergeArrays(jaEvaluatedItems, schema_output_GetEvaluatedItems(joResult));
        }
    }

    if (bAnnotate)
    {
        if (JsonGetLength(jaEvaluatedProperties) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", jaEvaluatedProperties);

        if (JsonGetLength(jaEvaluatedItems) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems);
    }

    schema_scope_PopSchemaPath();
    schema_debug_ExitFunction(__FUNCTION__);
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
    json joOutputUnit = schema_output_GetOutputUnit();
    schema_output_SetAnnotation(joOutputUnit, sKey, jValue);
    return joOutputUnit;
}

json schema_core_Validate(json jInstance, json joSchema)
{
    schema_debug_EnterFunction(__FUNCTION__);
    schema_debug_Argument(__FUNCTION__, "instance", jInstance);
    schema_debug_Argument(__FUNCTION__, "schema", joSchema);

    json joOutputUnit = schema_output_GetOutputUnit();
    json jaEvaluatedProperties = JsonArray();
    json jaEvaluatedItems = JsonArray();

    if (JsonGetType(joSchema) == JSON_TYPE_NULL)
    {
        schema_output_SetError(joOutputUnit, "schema is null", __FUNCTION__);
        schema_debug_ExitFunction(__FUNCTION__, "schema is null");
        schema_output_SetValid(joOutputUnit, FALSE);
        schema_output_SaveValidationResult(joOutputUnit);
        return joOutputUnit;
    }

    json jResult = JsonNull();
    if (joSchema == JSON_TRUE || joSchema == JsonObject())
    {
        schema_debug_ExitFunction(__FUNCTION__, "schema is true");
        schema_output_SetValid(joOutputUnit, TRUE);
        schema_output_SaveValidationResult(joOutputUnit);
        return joOutputUnit;
    }
    if (joSchema == JSON_FALSE)
    {
        schema_debug_ExitFunction(__FUNCTION__, "schema is false");
        schema_output_SetValid(joOutputUnit, FALSE);
        schema_output_SaveValidationResult(joOutputUnit);
        return joOutputUnit;
    }

    json jaSchemaKeys = JsonObjectKeys(joSchema);
    
    /// @brief Keep track of the current schema.  $schema should only be present in the root note
    ///     of any schema, so if it's present, assume that we're starting a new validation.
    int nLexicalScopes = 0;
    int nMapScopes = 0;
    string sSchema = JsonGetString(JsonObjectGet(joSchema, "$schema"));
    if (sSchema != "")
    {
        schema_scope_SetBaseSchema(joSchema);

        json jaKeyMap = schema_keyword_GetMap(sSchema);
        schema_scope_PushKeymap(jaKeyMap);
        nMapScopes++;
        
        // Only push to dynamic scope if we haven't already pushed via $id logic below
        // But wait, $id logic happens after this.
        // If this is root, it should be in dynamic scope.
        // If it has $id, it will be pushed again? No, we need to avoid double push.
        // Actually, if it has $id, the $id block will handle it.
        // If it DOES NOT have $id, but has $schema (root), we must push it.
        
        string sRootID = JsonGetString(JsonObjectGet(joSchema, "$id"));
        if (sRootID == "")
            sRootID = JsonGetString(JsonObjectGet(joSchema, "id"));

        if (sRootID == "")
        {
             schema_scope_PushLexical(joSchema);
             schema_scope_PushDynamic(joSchema);
             schema_scope_PushAbsoluteURI("");
             nLexicalScopes++;
        }

        json joIDMap = schema_util_MapIDs(joSchema, sRootID, JsonObject());
        SetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP", joIDMap);
    }
    else
    {
        json jaKeyMap = schema_scope_GetKeymap();
        if (JsonGetType(jaKeyMap) != JSON_TYPE_ARRAY || JsonGetLength(jaKeyMap) == 0)
        {
            jaKeyMap = schema_keyword_GetMap(SCHEMA_DEFAULT_DRAFT);
            schema_scope_PushKeymap(jaKeyMap);
            nMapScopes++;
        }
    }

    schema_debug_Message("sSchema is empty");

    /// @note Handle $id (or id) to establish new Base URI context.
    string sID = JsonGetString(JsonObjectGet(joSchema, "$id"));
    if (sID == "" && schema_keyword_IsActive("id"))
        sID = JsonGetString(JsonObjectGet(joSchema, "id"));

    if (sID != "")
    {
        // Resolve ID against current base schema
        string sBaseURI = schema_scope_GetBaseURI();
        
        // If we have a base URI, resolve the new ID against it
        if (sBaseURI != "")
        {
            sID = schema_reference_ResolveURI(sBaseURI, sID);
            
            /// @note Update the schema object with the absolute ID for the scope.
            ///     We create a shallow copy with the updated ID to push to the stack.
            ///     This ensures children resolve against the absolute URI.
            json joNewScope = JsonObjectSet(joSchema, "$id", JsonString(sID));
            schema_scope_PushLexical(joNewScope);
            schema_scope_PushDynamic(joNewScope);
            schema_scope_PushAbsoluteURI(sID);
            nLexicalScopes++;
        }
        else
        {
            /// @note If no base URI (e.g. root with relative ID?), just push as is.
            ///     But usually root has absolute ID or we treat it as such.
            schema_scope_PushLexical(joSchema);
            schema_scope_PushDynamic(joSchema);
            schema_scope_PushAbsoluteURI(sID);
            nLexicalScopes++;
        }
    }

    int bDynamicAnchor = FALSE;
    if (JsonFind(jaSchemaKeys, JsonString("$dynamicAnchor")) != JsonNull() ||
        JsonFind(jaSchemaKeys, JsonString("$recursiveAnchor")) != JsonNull())
    {
        // schema_scope_PushDynamic(joSchema);
        bDynamicAnchor = TRUE;
    }

    /// @brief Resolve references, dynamic references and recursive references.  Dynamic and recursive
    ///     references take advantage of dynamic scope to find the appropriate anchor/subschema.  If
    ///     dynamic or recursive references cannot be resolved for any reason, they revert to resolving
    ///     exactly like a normal $ref.
    
    json jRef = JsonObjectGet(joSchema, "$ref");
    if (JsonGetType(jRef) != JSON_TYPE_NULL)
    {
        schema_scope_PushSchemaPath("$ref");
        
        // schema_reference_ResolveRef logic inlined with context switching
        json joBaseSchema = schema_scope_GetBaseSchema();
        string sRef = JsonGetString(jRef);
        string sBaseURI = schema_scope_GetBaseURI();
        
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
        int bContextSwitch = FALSE;
        int bExternalLoad = FALSE;
        json joOldIDMap;
        
        if (sSchemaID == "" || sSchemaID == sBaseURI)
        {
            joTargetSchema = joBaseSchema;
        }
        else
        {
            // Check if the schema is already in the current ID map (internal reference)
            json joCurrentIDMap = GetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP");
            if (JsonGetType(joCurrentIDMap) == JSON_TYPE_OBJECT)
            {
                json joMapped = JsonObjectGet(joCurrentIDMap, sSchemaID);
                if (JsonGetType(joMapped) == JSON_TYPE_OBJECT)
                {
                    joTargetSchema = joMapped;
                    // It's an internal reference, so we switch scope but KEEP the ID map
                    // because we are still in the same document context.
                    bContextSwitch = TRUE;
                    schema_scope_PushLexical(joTargetSchema);
                    schema_scope_PushDynamic(joTargetSchema);
                }
            }

            // If not found internally, try to load it (external reference)
            if (JsonGetType(joTargetSchema) == JSON_TYPE_NULL)
            {
                joTargetSchema = schema_reference_GetSchema(sSchemaID);
                if (JsonGetType(joTargetSchema) == JSON_TYPE_OBJECT)
                {
                    bContextSwitch = TRUE;
                    bExternalLoad = TRUE;
                    schema_scope_PushLexical(joTargetSchema);
                    schema_scope_PushDynamic(joTargetSchema);
                    
                    // It's a new document, so we must map its IDs and replace the map
                    joOldIDMap = GetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP");
                    json joIDMap = schema_util_MapIDs(joTargetSchema, sSchemaID, JsonObject());
                    SetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP", joIDMap);
                }
                else
                {
                    joTargetSchema = JsonNull();
                }
            }
        }
        
        if (JsonGetType(joTargetSchema) != JSON_TYPE_NULL)
        {
            json jRefSchema;
            if (sFragment == "")
                jRefSchema = joTargetSchema;
            else
                jRefSchema = schema_reference_ResolveFragment(joTargetSchema, sFragment);
                
            if (JsonGetType(jRefSchema) != JSON_TYPE_NULL)
            {
                if (bExternalLoad) schema_scope_PushAbsoluteURI(sFullURI);
                jResult = schema_core_Validate(jInstance, jRefSchema);
                if (bExternalLoad) schema_scope_PopAbsoluteURI();
            }
        }
        
        if (bContextSwitch)
        {
            schema_scope_PopLexical();
            schema_scope_PopDynamic();
            // Only restore the ID map if we actually replaced it (i.e. it was not null)
            if (JsonGetType(joOldIDMap) != JSON_TYPE_NULL)
                SetLocalJson(GetModule(), "SCHEMA_SCOPE_IDMAP", joOldIDMap);
        }
        
        schema_scope_PopSchemaPath();
    }
    else
    {
        jRef = JsonObjectGet(joSchema, "$dynamicRef");
        if (JsonGetType(jRef) != JSON_TYPE_NULL && schema_keyword_IsActive("$dynamicRef"))
        {
            schema_scope_PushSchemaPath("$dynamicRef");
            
            // Calculate URI strictly for location tracking
            string sDynamicURI = schema_reference_ResolveDynamicRefURI(joSchema, jRef);
            schema_scope_PushAbsoluteURI(sDynamicURI);

            jResult = schema_core_Validate(jInstance, schema_reference_ResolveDynamicRef(joSchema, jRef, TRUE));
            
            schema_scope_PopAbsoluteURI();
            schema_scope_PopSchemaPath();
        }
        else
        {
            jRef = JsonObjectGet(joSchema, "$recursiveRef");
            if (JsonGetType(jRef) != JSON_TYPE_NULL && schema_keyword_IsActive("$recursiveRef"))
            {
                schema_scope_PushSchemaPath("$recursiveRef");
                
                // $recursiveRef (boolean true/false) is not supported for string resolution logic easily here
                // but if it is a string "#", it is dynamicRef.
                // Assuming URI resolution fallback to base + # for now unless we implement ResolveRecursiveRefURI
                
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
            {
                schema_output_InsertAnnotation(joOutputUnit, jResult);
                if (schema_keyword_IsModern())
                {
                    jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(jResult));
                    jaEvaluatedItems = schema_scope_MergeArrays(jaEvaluatedItems, schema_output_GetEvaluatedItems(jResult));
                }
            }
            else
                schema_output_InsertError(joOutputUnit, jResult);
        }
        else
        {
            /// @todo
            ///     [ ] What do we do with a JsonNull() return from $ref validation?
        }

        if (schema_keyword_IsLegacy())
        {
            if (bDynamicAnchor)
                schema_scope_PopDynamic();
            
            while (nLexicalScopes > 0)
            {
                schema_scope_PopLexical();
                schema_scope_PopDynamic();
                nLexicalScopes--;
            }

            while (nMapScopes > 0)
            {
                schema_scope_PopKeymap();
                nMapScopes--;
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
        json jaMapStack = schema_scope_GetKeymap();
        json jaKeyMap = JsonArrayGet(jaMapStack, JsonGetLength(jaMapStack) - 1);

        if (JsonFind(jaKeyMap, JsonString(sKey)) == JsonNull())
            continue;

        if (sKey == "$ref" || sKey == "$dynamicRef" || sKey == "$recursiveRef" || 
            sKey == "$schema" || sKey == "$id" || sKey == "id" || 
            sKey == "$defs" || sKey == "definitions" || 
            sKey == "$anchor" || sKey == "$dynamicAnchor" || sKey == "$recursiveAnchor")
            continue;

        if (sKey == "if" || sKey == "then" || sKey == "else")
        {
            if (!(nHandledFlags & HANDLED_CONDITIONAL))
            {
                jResult = schema_validate_Conditional(jInstance,
                    JsonObjectGet(joSchema, "if"),
                    JsonObjectGet(joSchema, "then"),
                    JsonObjectGet(joSchema, "else")
                );
                nHandledFlags |= HANDLED_CONDITIONAL;
            }
            else
                continue;
        }
        else if (sKey == "contains" || sKey == "minContains" || sKey == "maxContains")
        {
            if (!(nHandledFlags & HANDLED_CONTAINS))
            {
                jResult = schema_validate_Contains(jInstance,
                    JsonObjectGet(joSchema, "contains"),
                    JsonObjectGet(joSchema, "minContains"),
                    JsonObjectGet(joSchema, "maxContains")
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
                    JsonObjectGet(joSchema, "dependencies"),
                    JsonObjectGet(joSchema, "dependentSchemas")
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
                    JsonObjectGet(joSchema, "prefixItems"),
                    JsonObjectGet(joSchema, "items"),
                    JsonObjectGet(joSchema, "additionalItems")
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
            jResult = schema_validate_AllOf(jInstance, jKeySchema);
        else if (sKey == "anyOf")
            jResult = schema_validate_AnyOf(jInstance, jKeySchema);
        else if (sKey == "oneOf")
            jResult = schema_validate_OneOf(jInstance, jKeySchema);
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
            ///     the mix.
            int nResultLength = JsonGetLength(jResult);
            int i; for (; i < nResultLength; i++)
            {
                if (!schema_output_GetValid(JsonArrayGet(jResult, i)))
                    break;
            }

            int j; for (; j < nResultLength; j++)
            {
                json joResult = JsonArrayGet(jResult, j);
                if (i == nResultLength)
                    schema_output_InsertAnnotation(joOutputUnit, joResult);
                else
                    schema_output_InsertError(joOutputUnit, joResult);
                if (i == nResultLength && schema_keyword_IsModern())
                {
                    jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(joResult));
                    jaEvaluatedItems = schema_scope_MergeArrays(jaEvaluatedItems, schema_output_GetEvaluatedItems(joResult));
                }
            }
            
            if (SCHEMA_OUTPUT_INCLUDE_SOURCE)
                JsonObjectSetInplace(joOutputUnit, "source", JsonString(__FUNCTION__ + " (array)"));
 
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
            {
                schema_output_InsertAnnotation(joOutputUnit, jResult, sSource);
                if (schema_keyword_IsModern())
                {
                    jaEvaluatedProperties = schema_scope_MergeArrays(jaEvaluatedProperties, schema_output_GetEvaluatedProperties(jResult));
                    jaEvaluatedItems = schema_scope_MergeArrays(jaEvaluatedItems, schema_output_GetEvaluatedItems(jResult));
                }
            }
            else
                schema_output_InsertError(joOutputUnit, jResult, sSource);
        }
        else
            jResult = JsonObjectSet(JsonObject(), "valid", JsonBool(TRUE));
    }

    if (schema_keyword_IsModern() && schema_output_GetValid(joOutputUnit))
    {
        if (JsonGetLength(jaEvaluatedProperties) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedProperties", jaEvaluatedProperties);

        if (JsonGetLength(jaEvaluatedItems) > 0)
            schema_output_SetAnnotation(joOutputUnit, "evaluatedItems", jaEvaluatedItems);
    }

    schema_validate_Unevaluated(jInstance, joSchema, joOutputUnit);

    while (nLexicalScopes > 0)
    {
        schema_scope_PopLexical();
        schema_scope_PopDynamic();
        schema_scope_PopAbsoluteURI();
        nLexicalScopes--;
    }

    while (nMapScopes > 0)
    {
        schema_scope_PopKeymap();
        nMapScopes--;
    }

    schema_debug_ExitFunction(__FUNCTION__);
    return joOutputUnit;
}

/// -----------------------------------------------------------------------------------------------
///                                     PUBLIC API
/// -----------------------------------------------------------------------------------------------

int ValidateSchema(json joSchema)
{
    string sSchema = JsonGetString(JsonObjectGet(joSchema, "$schema"));
    if (sSchema == "")
        sSchema = SCHEMA_DEFAULT_DRAFT;

    json joMetaSchema = schema_reference_GetSchema(sSchema);
    if (JsonGetType(joMetaSchema) == JSON_TYPE_OBJECT)
    {
        schema_scope_Destroy();
        json joResult = schema_core_Validate(joSchema, joMetaSchema);

        if (schema_output_GetValid(joResult))
        {
            schema_reference_SaveSchema(joSchema);
            return TRUE;
        }
        else
            return FALSE;
    }
    else
        return FALSE;
}

int ValidateInstance(json jInstance, string sSchema)
{
    if (sSchema == "")
    {
        Error("[SCHEMA::" + __FUNCTION__ + "] sSchema not specified; validation failed");
        return FALSE;
    }

    json joSchema = schema_reference_GetSchema(sSchema);
    if (JsonGetType(joSchema) == JSON_TYPE_OBJECT)
    {
        schema_scope_Destroy();
        json joResult = schema_core_Validate(jInstance, joSchema);
        return schema_output_GetValid(joResult);
    }
    else
    {
        Error("[SCHEMA::" + __FUNCTION__ + "] sSchema (" + sSchema + ") not found; validation failed");
        return FALSE;
    }
}

int ValidateInstanceAdHoc(json jInstance, json joSchema)
{
    if (JsonGetType(joSchema) != JSON_TYPE_OBJECT)
    {
        Error("[SCHEMA::" + __FUNCTION__ + "] joSchema is not a valid schema object; validation failed");
        return FALSE;
    }

    schema_scope_Destroy();
    json joResult = schema_core_Validate(jInstance, joSchema);
    return schema_output_GetValid(joResult);
}
