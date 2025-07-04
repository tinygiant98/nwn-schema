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

void schema_suite_validate_minlength()
{
    json jaSuite = JsonParse(r"
        [
            {
                ""description"": ""minLength validation"",
                ""schema"": {
                    ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                    ""minLength"": 2
                },
                ""tests"": [
                    {
                        ""description"": ""longer is valid"",
                        ""data"": ""foo"",
                        ""valid"": true
                    },
                    {
                        ""description"": ""exact length is valid"",
                        ""data"": ""fo"",
                        ""valid"": true
                    },
                    {
                        ""description"": ""too short is invalid"",
                        ""data"": ""f"",
                        ""valid"": false
                    },
                    {
                        ""description"": ""ignores non-strings"",
                        ""data"": 1,
                        ""valid"": true
                    },
                    {
                        ""description"": ""one grapheme is not long enough"",
                        ""data"": ""\uD83D\uDCA9"",
                        ""valid"": false
                    }
                ]
            },
            {
                ""description"": ""minLength validation with a decimal"",
                ""schema"": {
                    ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                    ""minLength"": 2.0
                },
                ""tests"": [
                    {
                        ""description"": ""longer is valid"",
                        ""data"": ""foo"",
                        ""valid"": true
                    },
                    {
                        ""description"": ""too short is invalid"",
                        ""data"": ""f"",
                        ""valid"": false
                    }
                ]
            }
        ]
    ");


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
                json jData = JsonObjectGet(joTest, "data");
                json jbValid = JsonObjectGet(joTest, "valid");

                //json joResult = schema_validate_MinLength(jData, JsonPointer(joSchema, "/minLength"));
                json jInstance = jData;
                json joResult = schema_core_Validate(jInstance, joSchema);

                if (!Assert(JsonGetString(jsDescription), schema_output_GetValid(joResult) == JsonGetInt(jbValid)))
                    DescribeTestParameters(JsonDump(joTest), JsonDump(jbValid), JsonDump(JsonObjectGet(joResult, "valid")));
            }

            Outdent();
        }
    }
}

void main()
{

    DescribeTestSuite("Schema Core Unit Tests");
    schema_suite_validate_minlength();
}
    