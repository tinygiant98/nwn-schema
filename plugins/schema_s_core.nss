/// @brief this file will eventually hold all the 2020-12 schema definitions
///     that will only be used for building the database entries and if the
///     the database entries are lost.  Will need some versioning support.

void main()
{
    string sApplicator = r"{
        ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
        ""$id"": ""https://json-schema.org/draft/2020-12/meta/applicator"",
        ""$dynamicAnchor"": ""meta"",

        ""title"": ""Applicator vocabulary meta-schema"",
        ""type"": [""object"", ""boolean""],
        ""properties"": {
            ""prefixItems"": { ""$ref"": ""#/$defs/schemaArray"" },
            ""items"": { ""$dynamicRef"": ""#meta"" },
            ""contains"": { ""$dynamicRef"": ""#meta"" },
            ""additionalProperties"": { ""$dynamicRef"": ""#meta"" },
            ""properties"": {
                ""type"": ""object"",
                ""additionalProperties"": { ""$dynamicRef"": ""#meta"" },
                ""default"": {}
            },
            ""patternProperties"": {
                ""type"": ""object"",
                ""additionalProperties"": { ""$dynamicRef"": ""#meta"" },
                ""propertyNames"": { ""format"": ""regex"" },
                ""default"": {}
            },
            ""dependentSchemas"": {
                ""type"": ""object"",
                ""additionalProperties"": { ""$dynamicRef"": ""#meta"" },
                ""default"": {}
            },
            ""propertyNames"": { ""$dynamicRef"": ""#meta"" },
            ""if"": { ""$dynamicRef"": ""#meta"" },
            ""then"": { ""$dynamicRef"": ""#meta"" },
            ""else"": { ""$dynamicRef"": ""#meta"" },
            ""allOf"": { ""$ref"": ""#/$defs/schemaArray"" },
            ""anyOf"": { ""$ref"": ""#/$defs/schemaArray"" },
            ""oneOf"": { ""$ref"": ""#/$defs/schemaArray"" },
            ""not"": { ""$dynamicRef"": ""#meta"" }
        },
        ""$defs"": {
            ""schemaArray"": {
                ""type"": ""array"",
                ""minItems"": 1,
                ""items"": { ""$dynamicRef"": ""#meta"" }
            }
        }
    }";
}
