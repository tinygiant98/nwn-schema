/// ----------------------------------------------------------------------------
/// @file   util_t_argstack.nss
/// @author Ed Burke (tinygiant98) <af.hog.pilot@gmail.com>
/// @brief  Functions for unit-testing argument stacks.
/// ----------------------------------------------------------------------------

#include "util_i_unittest"
#include "schema_i_core2"

// @TESTSUITE[Schema Core]
// @TESTGROUP[Schema Validation]

// @TEST[Validate Global]
void schema_test_validate_Global()
{
    int t1, t2, t3, t4, t5, t6, t7, tGroup;
    int b1, b2, b3, b4, b5, b6, b7, bGroup;
    json r1, r2, r3, r4, r5, r6, r7;
    json e1, e2, e3, e4, e5, e6, e7;

    json jResultBase = schema_output_GetMinimalObject();

    /// @brief This group tests the output of `schema_validate_Type` against expected
    ///     output for a successful validation against a single type.
    e1 = schema_output_InsertAnnotation(jResultBase, "type", JsonString("null"));
    e2 = schema_output_InsertAnnotation(jResultBase, "type", JsonString("object"));
    e3 = schema_output_InsertAnnotation(jResultBase, "type", JsonString("array"));
    e4 = schema_output_InsertAnnotation(jResultBase, "type", JsonString("string"));
    e5 = schema_output_InsertAnnotation(jResultBase, "type", JsonString("number"));
    e6 = schema_output_InsertAnnotation(jResultBase, "type", JsonString("number"));
    e7 = schema_output_InsertAnnotation(jResultBase, "type", JsonString("boolean"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Type(JsonNull(), JsonString("null")); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Type(JsonObject(), JsonString("object")); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_Type(JsonArray(), JsonString("array")); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_Type(JsonString("test"), JsonString("string")); t4 = Timer(t4);
        t5 = Timer(); r5 = schema_validate_Type(JsonInt(5), JsonString("number")); t5 = Timer(t5);
        t6 = Timer(); r6 = schema_validate_Type(JsonFloat(5.0), JsonString("number")); t6 = Timer(t6);
        t7 = Timer(); r7 = schema_validate_Type(JsonBool(TRUE), JsonString("boolean")); t7 = Timer(t7);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2) &
             (b3 = r3 == e3) &
             (b4 = r4 == e4) &
             (b5 = r5 == e5) &
             (b6 = r6 == e6) &
             (b7 = r7 == e7);

    if (!AssertGroup("[type] Value Subschema (successful match)", bGroup))
    {
        if (!Assert("Null vs Single Type 'null'", b1))
            DescribeTestParameters(JsonDump(JsonNull()), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Object vs Single Type 'object'", b2))
            DescribeTestParameters(JsonDump(JsonObject()), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Array vs Single Type 'array'", b3))
            DescribeTestParameters(JsonDump(JsonArray()), JsonDump(e3), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("String vs Single Type 'string'", b4))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e4), JsonDump(r4));
        DescribeTestTime(t4);

        if (!Assert("Int vs Single Type 'number'", b5))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e5), JsonDump(r5));
        DescribeTestTime(t5);

        if (!Assert("Float vs Single Type 'number'", b6))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e6), JsonDump(r6));
        DescribeTestTime(t6);

        if (!Assert("Boolean vs Single Type 'boolean'", b7))
            DescribeTestParameters(JsonDump(JsonBool(TRUE)), JsonDump(e7), JsonDump(r7));
        DescribeTestTime(t7);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_Type` against expected
    ///     output for an unsuccessful validation against a single type.
    e1 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_type>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Type(JsonNull(), JsonString("string")); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Type(JsonObject(), JsonString("null")); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_Type(JsonArray(), JsonString("null")); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_Type(JsonString("test"), JsonString("null")); t4 = Timer(t4);
        t5 = Timer(); r5 = schema_validate_Type(JsonInt(5), JsonString("null")); t5 = Timer(t5);
        t6 = Timer(); r6 = schema_validate_Type(JsonFloat(5.0), JsonString("null")); t6 = Timer(t6);
        t7 = Timer(); r7 = schema_validate_Type(JsonBool(TRUE), JsonString("null")); t7 = Timer(t7);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e1) &
             (b3 = r3 == e1) &
             (b4 = r4 == e1) &
             (b5 = r5 == e1) &
             (b6 = r6 == e1) &
             (b7 = r7 == e1);

    if (!AssertGroup("[type] Value Subschema (unsuccessful match)", bGroup))
    {
        if (!Assert("Null vs Single Type 'null'", b1))
            DescribeTestParameters(JsonDump(JsonNull()), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Object vs Single Type 'object'", b2))
            DescribeTestParameters(JsonDump(JsonObject()), JsonDump(e1), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Array vs Single Type 'array'", b3))
            DescribeTestParameters(JsonDump(JsonArray()), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("String vs Single Type 'string'", b4))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e1), JsonDump(r4));
        DescribeTestTime(t4);

        if (!Assert("Int vs Single Type 'number'", b5))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e1), JsonDump(r5));
        DescribeTestTime(t5);

        if (!Assert("Float vs Single Type 'number'", b6))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e1), JsonDump(r6));
        DescribeTestTime(t6);

        if (!Assert("Boolean vs Single Type 'boolean'", b7))
            DescribeTestParameters(JsonDump(JsonBool(TRUE)), JsonDump(e1), JsonDump(r7));
        DescribeTestTime(t7);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_Type` against expected
    ///     output for a successful validation against a type array.
    json jTypes = JsonParse(r"[
        ""null"",
        ""object"",
        ""array"",
        ""string"",
        ""number"",
        ""boolean""
    ]");
    e1 = schema_output_InsertAnnotation(jResultBase, "type", jTypes);

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Type(JsonNull(), jTypes); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Type(JsonObject(), jTypes); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_Type(JsonArray(), jTypes); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_Type(JsonString("test"), jTypes); t4 = Timer(t4);
        t5 = Timer(); r5 = schema_validate_Type(JsonInt(5), jTypes); t5 = Timer(t5);
        t6 = Timer(); r6 = schema_validate_Type(JsonFloat(5.0), jTypes); t6 = Timer(t6);
        t7 = Timer(); r7 = schema_validate_Type(JsonBool(TRUE), jTypes); t7 = Timer(t7);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e1) &
             (b3 = r3 == e1) &
             (b4 = r4 == e1) &
             (b5 = r5 == e1) &
             (b6 = r6 == e1) &
             (b7 = r7 == e1);

    if (!AssertGroup("[type] Array Subschema (successful match)", bGroup))
    {
        if (!Assert("Null vs Type Array", b1))
            DescribeTestParameters(JsonDump(JsonNull()), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Object vs Type Array", b2))
            DescribeTestParameters(JsonDump(JsonObject()), JsonDump(e1), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Array vs Type Array", b3))
            DescribeTestParameters(JsonDump(JsonArray()), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("String vs Type Array", b4))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e1), JsonDump(r4));
        DescribeTestTime(t4);

        if (!Assert("Int vs Type Array", b5))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e1), JsonDump(r5));
        DescribeTestTime(t5);

        if (!Assert("Float vs Type Array", b6))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e1), JsonDump(r6));
        DescribeTestTime(t6);

        if (!Assert("Boolean vs Type Array", b7))
            DescribeTestParameters(JsonDump(JsonBool(TRUE)), JsonDump(e1), JsonDump(r7));
        DescribeTestTime(t7);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_Type` against expected
    ///     output for an unsuccessful validation against a type array.
    json jTypesA = JsonParse(r"[
        ""null"",
        ""object"",
        ""array""
    ]");
    json jTypesB = JsonParse(r"[
        ""string"",
        ""number"",
        ""boolean""
    ]");
    e1 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_type>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Type(JsonNull(), jTypesB); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Type(JsonObject(), jTypesB); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_Type(JsonArray(), jTypesB); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_Type(JsonString("test"), jTypesA); t4 = Timer(t4);
        t5 = Timer(); r5 = schema_validate_Type(JsonInt(5), jTypesA); t5 = Timer(t5);
        t6 = Timer(); r6 = schema_validate_Type(JsonFloat(5.0), jTypesA); t6 = Timer(t6);
        t7 = Timer(); r7 = schema_validate_Type(JsonBool(TRUE), jTypesA); t7 = Timer(t7);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e1) &
             (b3 = r3 == e1) &
             (b4 = r4 == e1) &
             (b5 = r5 == e1) &
             (b6 = r6 == e1) &
             (b7 = r7 == e1);

    if (!AssertGroup("[type] Array Subschema (unsuccessful match)", bGroup))
    {
        if (!Assert("Null vs Type Array", b1))
            DescribeTestParameters(JsonDump(JsonNull()), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Object vs Type Array", b2))
            DescribeTestParameters(JsonDump(JsonObject()), JsonDump(e1), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Array vs Type Array", b3))
            DescribeTestParameters(JsonDump(JsonArray()), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("String vs Type Array", b4))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e1), JsonDump(r4));
        DescribeTestTime(t4);

        if (!Assert("Int vs Type Array", b5))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e1), JsonDump(r5));
        DescribeTestTime(t5);

        if (!Assert("Float vs Type Array", b6))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e1), JsonDump(r6));
        DescribeTestTime(t6);

        if (!Assert("Boolean vs Type Array", b7))
            DescribeTestParameters(JsonDump(JsonBool(TRUE)), JsonDump(e1), JsonDump(r7));
        DescribeTestTime(t7);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This test validates the output of `schema_validate_Enum` against
    ///     expected output for a successful validation against a value array (enum)
    ///     or single value (const).
    json jEnum = JsonParse(r"[
        null,
        5
    ]");
    json jConst = JsonInt(5);

    e1 = schema_output_InsertAnnotation(jResultBase, "enum", jEnum);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_enum>") + "enum");

    e3 = schema_output_InsertAnnotation(jResultBase, "const", jConst);
    e4 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_enum>") + "const");

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Enum(JsonInt(5), jEnum); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Enum(JsonString("test"), jEnum); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_Const(JsonInt(5), jConst); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_Const(JsonString("test"), jConst); t4 = Timer(t4);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2) &
             (b3 = r3 == e3) &
             (b4 = r4 == e4);

    if (!AssertGroup("[enum]/[const] Subschema", bGroup))
    {
        if (!Assert("Enum Contains Value", b1))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Enum Does Not Contain Value", b2))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Value Matches Constant", b3))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e3), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("Value Doe Not Match Constant", b4))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e4), JsonDump(r4));
        DescribeTestTime(t4);
    } DescribeGroupTime(tGroup); Outdent();

}

void schema_test_validate_String()
{
    int t1, t2, tGroup;
    int b1, b2, bGroup;
    json r1, r2;
    json e1, e2;

    json jResultBase = schema_output_GetMinimalObject();
    json jiCriteria = JsonInt(5);

    /// @brief This group tests the output of `schema_validate_MinLength` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "minLength", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_minlength>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_MinLength(JsonString("test_string"), jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_MinLength(JsonString("test"), jiCriteria); t2 = Timer(t2);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2);

    if (!AssertGroup("[minLength]", bGroup))
    {
        if (!Assert("Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonString("test_string")), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_MaxLength` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "maxLength", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_maxlength>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_MaxLength(JsonString("test"), jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_MaxLength(JsonString("test_string"), jiCriteria); t2 = Timer(t2);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2);

    if (!AssertGroup("[maxLength]", bGroup))
    {
        if (!Assert("Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonString("test_string")), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_Pattern` against expected
    ///     output for a successful validation.
    json jPattern = JsonString("^test_.*$");

    e1 = schema_output_InsertAnnotation(jResultBase, "pattern", jPattern);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_pattern>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Pattern(JsonString("test_string"), jPattern); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Pattern(JsonString("test"), jPattern); t2 = Timer(t2);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2);

    if (!AssertGroup("[pattern]", bGroup))
    {
        if (!Assert("Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonString("test_string")), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonString("test")), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);
    } DescribeGroupTime(tGroup); Outdent();

    /// @todo FORMAT
}

void schema_test_validate_Numeric()
{
    int t1, t2, t3, t4, tGroup;
    int b1, b2, b3, b4, bGroup;
    json r1, r2, r3, r4;
    json e1, e2, e3, e4;

    json jResultBase = schema_output_GetMinimalObject();
    json jiCriteria = JsonInt(5);

    /// @brief This group tests the output of `schema_validate_Maximum` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "maximum", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_maximum>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Maximum(JsonInt(5), jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Maximum(JsonInt(6), jiCriteria); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_Maximum(JsonFloat(5.0), jiCriteria); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_Maximum(JsonFloat(5.1), jiCriteria); t4 = Timer(t4);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2) &
             (b3 = r3 == e1) &
             (b4 = r4 == e2);

    if (!AssertGroup("[maximum]", bGroup))
    {
        if (!Assert("Integer Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Integer Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonInt(6)), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Float Instance Meets Constraint", b3))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("Float Instance Does Not Meet Constraint", b4))
            DescribeTestParameters(JsonDump(JsonFloat(5.1)), JsonDump(e2), JsonDump(r4));
        DescribeTestTime(t4);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_Minimum` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "minimum", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_minimum>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_Minimum(JsonInt(5), jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_Minimum(JsonInt(4), jiCriteria); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_Minimum(JsonFloat(5.0), jiCriteria); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_Minimum(JsonFloat(4.9), jiCriteria); t4 = Timer(t4);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2) &
             (b3 = r3 == e1) &
             (b4 = r4 == e2);

    if (!AssertGroup("[minimum]", bGroup))
    {
        if (!Assert("Integer Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Integer Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonInt(4)), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Float Instance Meets Constraint", b3))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("Float Instance Does Not Meet Constraint", b4))
            DescribeTestParameters(JsonDump(JsonFloat(4.9)), JsonDump(e2), JsonDump(r4));
        DescribeTestTime(t4);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_ExclusiveMaximum` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "exclusiveMaximum", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_exclusivemaximum>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_ExclusiveMaximum(JsonInt(4), jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_ExclusiveMaximum(JsonInt(5), jiCriteria); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_ExclusiveMaximum(JsonFloat(4.9), jiCriteria); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_ExclusiveMaximum(JsonFloat(5.0), jiCriteria); t4 = Timer(t4);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2) &
             (b3 = r3 == e1) &
             (b4 = r4 == e2);

    if (!AssertGroup("[exclusiveMaximum]", bGroup))
    {
        if (!Assert("Integer Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonInt(4)), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Integer Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Float Instance Meets Constraint", b3))
            DescribeTestParameters(JsonDump(JsonFloat(4.9)), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("Float Instance Does Not Meet Constraint", b4))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e2), JsonDump(r4));
        DescribeTestTime(t4);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_ExclusiveMinimum` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "exclusiveMinimum", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_exclusiveminimum>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_ExclusiveMinimum(JsonInt(6), jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_ExclusiveMinimum(JsonInt(5), jiCriteria); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_ExclusiveMinimum(JsonFloat(5.1), jiCriteria); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_ExclusiveMinimum(JsonFloat(5.0), jiCriteria); t4 = Timer(t4);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2) &
             (b3 = r3 == e1) &
             (b4 = r4 == e2);

    if (!AssertGroup("[exclusiveMinimum]", bGroup))
    {
        if (!Assert("Integer Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonInt(6)), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Integer Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonInt(5)), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Float Instance Meets Constraint", b3))
            DescribeTestParameters(JsonDump(JsonFloat(5.1)), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("Float Instance Does Not Meet Constraint", b4))
            DescribeTestParameters(JsonDump(JsonFloat(5.0)), JsonDump(e2), JsonDump(r4));
        DescribeTestTime(t4);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_MultipleOf` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "multipleOf", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_multipleof>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_MultipleOf(JsonInt(10), jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_MultipleOf(JsonInt(7), jiCriteria); t2 = Timer(t2);
        t3 = Timer(); r3 = schema_validate_MultipleOf(JsonFloat(10.0), jiCriteria); t3 = Timer(t3);
        t4 = Timer(); r4 = schema_validate_MultipleOf(JsonFloat(7.0), jiCriteria); t4 = Timer(t4);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2) &
             (b3 = r3 == e1) &
             (b4 = r4 == e2);

    if (!AssertGroup("[multipleOf]", bGroup))
    {
        if (!Assert("Integer Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(JsonInt(10)), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Integer Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(JsonInt(7)), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);

        if (!Assert("Float Instance Meets Constraint", b3))
            DescribeTestParameters(JsonDump(JsonFloat(10.0)), JsonDump(e1), JsonDump(r3));
        DescribeTestTime(t3);

        if (!Assert("Float Instance Does Not Meet Constraint", b4))
            DescribeTestParameters(JsonDump(JsonFloat(7.0)), JsonDump(e2), JsonDump(r4));
        DescribeTestTime(t4);
    } DescribeGroupTime(tGroup); Outdent();
}

void schema_test_validate_Array()
{
    int t1, t2, t3, t4, tGroup;
    int b1, b2, b3, b4, bGroup;
    json r1, r2, r3, r4;
    json e1, e2, e3, e4;

    json jResultBase = schema_output_GetMinimalObject();
    json jiCriteria = JsonInt(3);

    json jArray1 = JsonParse(r"[
        ""item1"",
        27,
        false
    ]");
    json jArray2 = JsonParse(r"[
        null,
        7
    ]");
    json jArray3 = JsonParse(r"[
        ""item1"",
        27,
        false,
        null,
        7,
        false
    ]");

    /// @brief This group tests the output of `schema_validate_MinItems` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "minItems", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_minitems>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_MinItems(jArray1, jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_MinItems(jArray2, jiCriteria); t2 = Timer(t2);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2);

    if (!AssertGroup("[maxItems]", bGroup))
    {
        if (!Assert("Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(jArray1), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(jArray2), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_MaxItems` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "maxItems", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_maxitems>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_MaxItems(jArray1, jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_MaxItems(jArray3, jiCriteria); t2 = Timer(t2);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2);

    if (!AssertGroup("[maxItems]", bGroup))
    {
        if (!Assert("Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(jArray1), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(jArray3), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);
    } DescribeGroupTime(tGroup); Outdent();

    /// @brief This group tests the output of `schema_validate_UniqueItems` against expected
    ///     output for a successful validation.
    e1 = schema_output_InsertAnnotation(jResultBase, "uniqueItems", jiCriteria);
    e2 = schema_output_InsertError(jResultBase, schema_output_GetErrorMessage("<validate_uniqueitems>"));

    tGroup = Timer();
    {
        t1 = Timer(); r1 = schema_validate_UniqueItems(jArray1, jiCriteria); t1 = Timer(t1);
        t2 = Timer(); r2 = schema_validate_UniqueItems(jArray3, jiCriteria); t2 = Timer(t2);
    }
    tGroup = Timer(tGroup);

    bGroup = (b1 = r1 == e1) &
             (b2 = r2 == e2);

    if (!AssertGroup("[uniqueItems]", bGroup))
    {
        if (!Assert("Instance Meets Constraint", b1))
            DescribeTestParameters(JsonDump(jArray1), JsonDump(e1), JsonDump(r1));
        DescribeTestTime(t1);

        if (!Assert("Instance Does Not Meet Constraint", b2))
            DescribeTestParameters(JsonDump(jArray3), JsonDump(e2), JsonDump(r2));
        DescribeTestTime(t2);
    } DescribeGroupTime(tGroup); Outdent();

    /// @todo schema_validate_Array()
}

void schema_test_validate_Object()
{}

void schema_test_validate_Applicator()
{}

void schema_test_validate_Metadata()
{}

void schema_test_validate_Output()
{}

void main()
{
    DescribeTestSuite("Schema Core Unit Tests");

    DescribeTestSuite("  Global Keyword Validation");
    schema_test_validate_Global();

    DescribeTestSuite("  String Keyword Validation");
    schema_test_validate_String();

    DescribeTestSuite("  Numeric Keyword Validation");
    schema_test_validate_Numeric();

    DescribeTestSuite("  Array Keyword Validation");
    schema_test_validate_Array();

    DescribeTestSuite("  Object Keyword Validation");
    schema_test_validate_Object();

    DescribeTestSuite("  Applicator Keyword Validation");
    schema_test_validate_Applicator();

    DescribeTestSuite("  Metadata Keyword Validation");
    schema_test_validate_Metadata();

    DescribeTestSuite("  Output Validation");
    schema_test_validate_Output();
}
    