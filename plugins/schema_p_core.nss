// -----------------------------------------------------------------------------
//    File: schema_p_core.nss
//  System: Json Schema Development Plugin
// -----------------------------------------------------------------------------

#include "core_i_framework"
#include "chat_i_main"
#include "util_i_debug"
#include "util_i_library"
#include "util_i_unittest"

#include "schema_i_core"

#include "nw_inc_nui"

void schema_OnPlayerChat()
{
    object oPC = GetPCChatSpeaker();

    int TEST = CountChatArguments(oPC) == 0 ? 0 : StringToInt(GetChatArgument(oPC));
    if (TEST == 0)
        ExecuteScript("schema_t_core");
    else if (TEST == 1)
    {
        SetLocalInt(GetModule(), "LOAD_SCHEMA", TRUE);
        ExecuteScript("schema_t_core");
        DeleteLocalInt(GetModule(), "LOAD_SCHEMA");
    }
    else if (TEST == 2)
    {
        json j1 = JsonParse(r"[""value1"", ""value2"", ""value3""]");

        {
            int t = Timer(); json j = JsonFind(j1, JsonString("value2")); t = Timer(t);
            Debug("JsonFind Test:");
            Debug("  JsonFind Result -> " + JsonDump(j));
            Debug("  JsonFine Time -> " + IntToString(t));
        }

        {
            int t = Timer();
            json j2 = JsonArrayInsert(JsonArray(), JsonString("value2"));
            json j = JsonSetOp(j1, JSON_SET_INTERSECT, j2);
            t = Timer(t);

            Debug("JsonSetOp Test:");
            Debug("  JsonSetOp Result -> " + JsonDump(j));
            Debug("  JsonSetOp Time -> " + IntToString(t));
        }
    }
    else if (TEST == 3)
    {

        //json JsonArrayGetRange(json jArray, int nBeginIndex, int nEndIndex);

        json jInstance = JsonParse("[1,2,3]");
        int nInstance = JsonGetLength(jInstance);

        json jItems = JsonParse("[1,2,3,4]");
        int nItems = JsonGetLength(jItems);

        json j = JsonArrayGetRange(jInstance, nItems, nInstance + 1);

        Debug("j = " + JsonDump(j));


    }
    else if (TEST == 4)
    {
        object oPC = GetPCChatSpeaker();

        json jWidget = NuiImage(JsonString("po_dw_f_01_s"), JsonInt(NUI_ASPECT_STRETCH), JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_TOP));
        jWidget = NuiImageRegion(jWidget, NuiRect(0.0, 0.0, 32.0, 50.0));
        jWidget = NuiHeight(jWidget, 56.0);
        jWidget = NuiWidth(jWidget, 36.0);

        json jColumn = JsonArrayInsert(JsonArray(), jWidget);
        json jRow = JsonArrayInsert(JsonArray(), NuiCol(jColumn));

        jWidget = NuiButtonImage(JsonString("beamdoge"));
        jWidget = NuiHeight(jWidget, 29.0);
        jWidget = NuiWidth(jWidget, 29.0);
        jWidget = NuiMargin(jWidget, 0.0);
        int i; for (; i < 4; i++)
        {
            jColumn = JsonArrayInsert(JsonArray(), jWidget);
            jColumn = JsonArrayInsert(jColumn, jWidget);
            jRow = JsonArrayInsert(jRow, NuiCol(jColumn));
        }
        
        json jRoot = NuiRow(jRow);
        json jWindow = NuiWindow(jRoot, JsonString(""), NuiBind("geometry"), JsonBool(TRUE), JsonBool(FALSE), JsonBool(TRUE), JsonBool(FALSE), JsonBool(TRUE));
        
        SendMessageToPC(oPC, JsonDump(jWindow, 4));

        int nToken = NuiCreate(oPC, jWindow);
        NuiSetBind(oPC, nToken, "geometry", NuiRect(100.0f, 100.0f, 250.0, 150.0));
    }
}


/*
void schema_OnPlayerChat()
{
    object oPC = GetPCChatSpeaker();

//    schema_Initialize(TRUE);

    //Warning(JsonDump(schema_GetVocabulary(), 4));

    Debug("Pulling valid and invalid schema from text files...");
    json jValid = JsonParse(ResManGetFileContents("schema-valid", RESTYPE_TXT));
    //json jInvalid = JsonParse(ResManGetFileContents("schema-invalid", RESTYPE_TXT));

    Debug("  Valid: " + (jValid == JSON_NULL ? "NULL" : "OK"));
    //Debug("  Invalid: " + (jInvalid == JSON_NULL ? "NULL" : "OK"));



    json jValidResults = schema_Validate(jValid, schema_GetVocabulary());
    //json jInvalidResults = schema_Validate(jInvalid, schema_GetVocabulary());

    Notice("VALID RESULTS:");
    Notice(JsonDump(jValidResults, 4));
    Notice("\n\n");

    //Notice("INVALID RESULTS:");
    //Notice(JsonDump(jInvalidResults, 4));

//    json jVocab = schema_GetVocabulary();
//    Notice(JsonDump(jVocab, 4));
//
//    Notice("Parsing NWN JSON File...");
//    json jNWN = JsonParse(ResManGetFileContents("nwn", RESTYPE_TXT));
//    Notice(JsonDump(jNWN));

    string s = r"
        WITH 
            result(data) AS (
                SELECT :result
            ),
            result_tree AS (
                SELECT * FROM result, json_tree(result.data)
            ),
            result_errors AS (
                SELECT json_group_array(child.value) AS errors
                FROM result_tree AS parent
                JOIN result_tree AS child ON child.parent = parent.id
                WHERE parent.type = 'array'
                    AND child.type = 'object'
            )
        SELECT
            CASE
                WHEN json_array_length(COALESCE(errors, '[]')) > 0
                    THEN json_object('valid', 0, 'errors', errors)
                    ELSE
                        json_object('valid', 1)
            END
        FROM result_errors;
    ";

    //s = r"
    //    WITH input(data) AS (
    //        SELECT :output
    //    )
    //    SELECT input.data FROM input;
    //";

    json jOutput = JsonParse(ResManGetFileContents("schema-output", RESTYPE_TXT));

    sqlquery q = SqlPrepareQueryObject(GetModule(), s);
    SqlBindJson(q, ":result", jOutput);

    if (SqlStep(q))
    {
        Notice("Query executed successfully.");
        json jResult = SqlGetJson(q, 0);

        Notice("Resulting JSON Array:");
        Notice(JsonDump(jResult, 4));
    }

}
*/

// -----------------------------------------------------------------------------
//                               Library Dispatch
// -----------------------------------------------------------------------------

void OnLibraryLoad()
{
    if (!GetIfPluginExists("json_schema"))
    {
        object oPlugin = CreatePlugin("json_vjson_schemaalidation");
        SetName(oPlugin, "[Plugin] System :: JSON Schema Validation Development");
        SetDebugPrefix(HexColorString("[JSON_SCHEMA]", COLOR_PINK), oPlugin);

        RegisterEventScript(oPlugin, CHAT_PREFIX + "!schema", "schema_OnPlayerChat");

        int n = 0;
        RegisterLibraryScript("schema_OnPlayerChat", n++);
    }
}

void OnLibraryScript(string sScript, int nEntry)
{
    int n = nEntry / 100 * 100;
    switch (n)
    {
        case 0:
        {
            if      (nEntry == n++) schema_OnPlayerChat();
        } break;

        default: CriticalError(__FILE__ + ": library function " + sScript + " not found");
    }
}
