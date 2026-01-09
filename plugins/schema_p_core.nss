// -----------------------------------------------------------------------------
//    File: schema_p_core.nss
//  System: Json Schema Development Plugin
// -----------------------------------------------------------------------------

#include "core_i_framework"
#include "chat_i_main"

#include "util_i_schema"
#include "util_i_library"

void schema_OnPlayerChat()
{
    object oPC = GetPCChatSpeaker();

    if (HasChatOption(oPC, "test"))
    {
        SetLocalInt(GetModule(), "SCHEMA_VALIDATION_DEBUGGING", HasChatOption(oPC, "debug"));
        schema_test_RunTestSuiteFromFile();
    }
}

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
