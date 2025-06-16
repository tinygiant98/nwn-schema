// -----------------------------------------------------------------------------
//    File: schema_p_core.nss
//  System: Json Schema Development Plugin
// -----------------------------------------------------------------------------

#include "core_i_framework"
#include "chat_i_main"
#include "util_i_debug"
#include "util_i_library"
#include "util_i_unittest"

//#include "schema_i_core"
#include "schema_i_core2"

void schema_OnPlayerChat()
{
    object oPC = GetPCChatSpeaker();

    if (HasChatOption(oPC, "schema"))
    {
        json joOutput = schema_output_GetOutputObject();
        Debug(JsonDump(joOutput), 4);
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

        RegisterEventScript(oPlugin, CHAT_PREFIX + "!json", "schema_OnPlayerChat");

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
