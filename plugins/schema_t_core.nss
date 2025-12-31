/// ----------------------------------------------------------------------------
/// @file   util_t_argstack.nss
/// @author Ed Burke (tinygiant98) <af.hog.pilot@gmail.com>
/// @brief  Functions for unit-testing argument stacks.
/// ----------------------------------------------------------------------------

#include "util_i_unittest"
#include "schema_i_core"

#include "util_i_debug"

// @TESTSUITE[Schema Core]
// @TESTGROUP[Schema Validation]

void schema_suite_RunTest(json joTest, json joSchema)
{
    json jsDescription = JsonObjectGet(joTest, "description");
    json jInstance = JsonObjectGet(joTest, "data");
    json jbValid = JsonObjectGet(joTest, "valid");
    
    int bValid = ValidateInstanceAdHoc(jInstance, joSchema);

    if (!Assert(JsonGetString(jsDescription), bValid == JsonGetInt(jbValid)))
    {
        DescribeTestParameters(JsonDump(joTest), JsonDump(jbValid), JsonDump(JsonBool(bValid)));
        Debug(HexColorString(JsonDump(schema_output_GetValidationResult(), 4), COLOR_BLUE_LIGHT));
    }
}

void schema_suite_RunTestSuiteFromFile()
{
    json jaSuite = JsonParse(ResManGetFileContents("test", RESTYPE_TXT));
    int i; for (; i < JsonGetLength(jaSuite); i++)
    {
        json joGroup = JsonArrayGet(jaSuite, i);
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
                //Debug(HexColorString(JsonDump(schema_output_GetValidationResult(), 4), COLOR_BLUE_LIGHT));
            } Outdent();
        }
    }
}

void main()
{
    DescribeTestSuite("Schema Core Unit Tests");
    schema_suite_RunTestSuiteFromFile();
}
    