#include "util_i_debug"

int DEBUG=FALSE;

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

void schema_debug_EnterFunction(string sFunction)
{
    if (!DEBUG) return;

    int n = GetLocalInt(GetModule(), sFunction);
    SetLocalInt(GetModule(), sFunction, ++n);
    Debug(schema_debug_GetIndent() + HexColorString("-> " + sFunction, COLOR_GREEN_LIGHT) + " " + HexColorString("(" + IntToString(n) + ")", COLOR_BLUE_LIGHT));

    schema_debug_Indent();
}

void schema_debug_ExitFunction(string sFunction)
{
    if (!DEBUG) return;

    schema_debug_Outdent();

    int n = GetLocalInt(GetModule(), sFunction);
    Debug(schema_debug_GetIndent() + HexColorString("<- " + sFunction, COLOR_RED_LIGHT) + " " + HexColorString("(" + IntToString(n) + ")", COLOR_BLUE_LIGHT));
    SetLocalInt(GetModule(), sFunction, --n);
}

void schema_debug_Argument(string sFunction, string sArg, json jValue)
{
    if (!DEBUG) return;

    Debug(schema_debug_GetIndent() + HexColorString(sArg + ": ", COLOR_BLUE_STEEL) + HexColorString(JsonDump(jValue), COLOR_BLUE_LIGHT));
}

void schema_debug_Message(string sMessage)
{
    if (!DEBUG) return;

    Debug(schema_debug_GetIndent() + sMessage);
}

void schema_debug_Value(string sTitle, string sValue)
{
    if (!DEBUG) return;
    Debug(schema_debug_GetIndent() + sTitle + " = " + HexColorString(sValue, COLOR_MAGENTA));
}

void schema_debug_Json(string sTitle, json jValue)
{
    if (!DEBUG) return;
    Debug(schema_debug_GetIndent() + sTitle);
    Debug(HexColorString(JsonDump(jValue, 4), COLOR_SALMON));
}

void schema_debug_JsonType(string sTitle, json jValue)
{
    string sType;
    switch (JsonGetType(jValue))
    {
        case JSON_TYPE_NULL: sType = "null"; break;
        case JSON_TYPE_OBJECT: sType = "object"; break;
        case JSON_TYPE_ARRAY: sType = "array"; break;
        case JSON_TYPE_STRING: sType = "string"; break;
        case JSON_TYPE_INTEGER: sType = "integer"; break;
        case JSON_TYPE_FLOAT: sType = "float"; break;
        case JSON_TYPE_BOOL: sType = "bool"; break;
        default: sType = "unknown";
    }

    Debug(schema_debug_GetIndent() + sTitle + " type = " + HexColorString(sType, COLOR_CYAN_DARK));
}