
/// @brief This default metaschema draft will be used anytime a user provide a custom
///     schema to be validated and has not provided a valid $schema key (either the
///     key was not included or doesn't exist within the schema database).
const string SCHEMA_DEFAULT_DRAFT = "https://json-schema.org/draft/2020-12/schema";

/// @note The schema validation system uses database tables to save and quickly access
///     informatin about previously used schema. The following three functions determine
///     where schema data is persistently stored.
/// @warning Once this system has been used and schema data loaded, changing the return
///     values of these functions may cause data loss.

/// @brief The return value of this function determines which database file schema data will
///     be persistently saved to.
string schema_GetDatabaseName()
{
    return "schema_system";
}

/// @brief The return value of this function determines which database table the schema-
///     specific data will be saved to.  This table will hold all schema data, identifiers,
///     and keymaps.
string schema_GetSchemaTableName()
{
    return "schema_schema";
}

/// @brief The return value of this function determines which database table the output-
///     specific data will be saved to.  This table holds resolved skeletons of various
///     output nodes for quick retrieval during the validation process.
/// @warning This table is not normally accessed by any systems outside the validation
///     system and should not be modified.
string schema_GetOutputTableName()
{
    return "schema_output";
}

/// @note This function contains all valid json-schema.org provided schema.  If a new version is released, simply
///     add the associated schema and vocabularies here.  Trusted metaschema are loaded in reverse chronological
///     order to ensure all available vocabulary-defined schema are available during the loading process to define
///     keyword maps, so if a new metaschema is published, add it after the next most-recent metaschema.
/// @note This implementation has some limitations.  For example, you'll need to replace all single-double quotes
///     with double-double quotes.  This can be done with a simple regex search and replace within vscode:
///         Search: "(.*?)"
///         Replace: "$1"
///     Additionally, escaped strings, for some reason, do not sit well with raw strings.  So those also need
///     to be removed with the same process:
///         Search: \\"(.*?)\\"
///         Replace: $1
/// @note This methodology was selected as a consistent method to initially populate schema tables with json-schema.org
///     metaschema without including additional files.  Official drafts are not expected to change, so this
///     function should only require updating when a new official meta schema is released by json-schema.org.
json schema_core_GetTrustedSchema(int bLoadTestSuiteFiles = FALSE)
{
    json jaTrustedSchema = JsonArray();

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""id"": ""http://json-schema.org/draft-04/schema#"",
            ""$schema"": ""http://json-schema.org/draft-04/schema#"",
            ""description"": ""Core schema meta-schema"",
            ""definitions"": {
                ""schemaArray"": {
                    ""type"": ""array"",
                    ""minItems"": 1,
                    ""items"": { ""$ref"": ""#"" }
                },
                ""positiveInteger"": {
                    ""type"": ""integer"",
                    ""minimum"": 0
                },
                ""positiveIntegerDefault0"": {
                    ""allOf"": [ { ""$ref"": ""#/definitions/positiveInteger"" }, { ""default"": 0 } ]
                },
                ""simpleTypes"": {
                    ""enum"": [ ""array"", ""boolean"", ""integer"", ""null"", ""number"", ""object"", ""string"" ]
                },
                ""stringArray"": {
                    ""type"": ""array"",
                    ""items"": { ""type"": ""string"" },
                    ""minItems"": 1,
                    ""uniqueItems"": true
                }
            },
            ""type"": ""object"",
            ""properties"": {
                ""id"": {
                    ""type"": ""string""
                },
                ""$schema"": {
                    ""type"": ""string""
                },
                ""title"": {
                    ""type"": ""string""
                },
                ""description"": {
                    ""type"": ""string""
                },
                ""default"": {},
                ""multipleOf"": {
                    ""type"": ""number"",
                    ""minimum"": 0,
                    ""exclusiveMinimum"": true
                },
                ""maximum"": {
                    ""type"": ""number""
                },
                ""exclusiveMaximum"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""minimum"": {
                    ""type"": ""number""
                },
                ""exclusiveMinimum"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""maxLength"": { ""$ref"": ""#/definitions/positiveInteger"" },
                ""minLength"": { ""$ref"": ""#/definitions/positiveIntegerDefault0"" },
                ""pattern"": {
                    ""type"": ""string"",
                    ""format"": ""regex""
                },
                ""additionalItems"": {
                    ""anyOf"": [
                        { ""type"": ""boolean"" },
                        { ""$ref"": ""#"" }
                    ],
                    ""default"": {}
                },
                ""items"": {
                    ""anyOf"": [
                        { ""$ref"": ""#"" },
                        { ""$ref"": ""#/definitions/schemaArray"" }
                    ],
                    ""default"": {}
                },
                ""maxItems"": { ""$ref"": ""#/definitions/positiveInteger"" },
                ""minItems"": { ""$ref"": ""#/definitions/positiveIntegerDefault0"" },
                ""uniqueItems"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""maxProperties"": { ""$ref"": ""#/definitions/positiveInteger"" },
                ""minProperties"": { ""$ref"": ""#/definitions/positiveIntegerDefault0"" },
                ""required"": { ""$ref"": ""#/definitions/stringArray"" },
                ""additionalProperties"": {
                    ""anyOf"": [
                        { ""type"": ""boolean"" },
                        { ""$ref"": ""#"" }
                    ],
                    ""default"": {}
                },
                ""definitions"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""default"": {}
                },
                ""properties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""default"": {}
                },
                ""patternProperties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""default"": {}
                },
                ""dependencies"": {
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""anyOf"": [
                            { ""$ref"": ""#"" },
                            { ""$ref"": ""#/definitions/stringArray"" }
                        ]
                    }
                },
                ""enum"": {
                    ""type"": ""array"",
                    ""minItems"": 1,
                    ""uniqueItems"": true
                },
                ""type"": {
                    ""anyOf"": [
                        { ""$ref"": ""#/definitions/simpleTypes"" },
                        {
                            ""type"": ""array"",
                            ""items"": { ""$ref"": ""#/definitions/simpleTypes"" },
                            ""minItems"": 1,
                            ""uniqueItems"": true
                        }
                    ]
                },
                ""format"": { ""type"": ""string"" },
                ""allOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""anyOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""oneOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""not"": { ""$ref"": ""#"" }
            },
            ""dependencies"": {
                ""exclusiveMaximum"": [ ""maximum"" ],
                ""exclusiveMinimum"": [ ""minimum"" ]
            },
            ""default"": {}
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""http://json-schema.org/draft-06/schema#"",
            ""$id"": ""http://json-schema.org/draft-06/schema#"",
            ""title"": ""Core schema meta-schema"",
            ""definitions"": {
                ""schemaArray"": {
                    ""type"": ""array"",
                    ""minItems"": 1,
                    ""items"": { ""$ref"": ""#"" }
                },
                ""nonNegativeInteger"": {
                    ""type"": ""integer"",
                    ""minimum"": 0
                },
                ""nonNegativeIntegerDefault0"": {
                    ""allOf"": [
                        { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                        { ""default"": 0 }
                    ]
                },
                ""simpleTypes"": {
                    ""enum"": [
                        ""array"",
                        ""boolean"",
                        ""integer"",
                        ""null"",
                        ""number"",
                        ""object"",
                        ""string""
                    ]
                },
                ""stringArray"": {
                    ""type"": ""array"",
                    ""items"": { ""type"": ""string"" },
                    ""uniqueItems"": true,
                    ""default"": []
                }
            },
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""$id"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference""
                },
                ""$schema"": {
                    ""type"": ""string"",
                    ""format"": ""uri""
                },
                ""$ref"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference""
                },
                ""title"": {
                    ""type"": ""string""
                },
                ""description"": {
                    ""type"": ""string""
                },
                ""default"": {},
                ""examples"": {
                    ""type"": ""array"",
                    ""items"": {}
                },
                ""multipleOf"": {
                    ""type"": ""number"",
                    ""exclusiveMinimum"": 0
                },
                ""maximum"": {
                    ""type"": ""number""
                },
                ""exclusiveMaximum"": {
                    ""type"": ""number""
                },
                ""minimum"": {
                    ""type"": ""number""
                },
                ""exclusiveMinimum"": {
                    ""type"": ""number""
                },
                ""maxLength"": { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                ""minLength"": { ""$ref"": ""#/definitions/nonNegativeIntegerDefault0"" },
                ""pattern"": {
                    ""type"": ""string"",
                    ""format"": ""regex""
                },
                ""additionalItems"": { ""$ref"": ""#"" },
                ""items"": {
                    ""anyOf"": [
                        { ""$ref"": ""#"" },
                        { ""$ref"": ""#/definitions/schemaArray"" }
                    ],
                    ""default"": {}
                },
                ""maxItems"": { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                ""minItems"": { ""$ref"": ""#/definitions/nonNegativeIntegerDefault0"" },
                ""uniqueItems"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""contains"": { ""$ref"": ""#"" },
                ""maxProperties"": { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                ""minProperties"": { ""$ref"": ""#/definitions/nonNegativeIntegerDefault0"" },
                ""required"": { ""$ref"": ""#/definitions/stringArray"" },
                ""additionalProperties"": { ""$ref"": ""#"" },
                ""definitions"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""default"": {}
                },
                ""properties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""default"": {}
                },
                ""patternProperties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""propertyNames"": { ""format"": ""regex"" },
                    ""default"": {}
                },
                ""dependencies"": {
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""anyOf"": [
                            { ""$ref"": ""#"" },
                            { ""$ref"": ""#/definitions/stringArray"" }
                        ]
                    }
                },
                ""propertyNames"": { ""$ref"": ""#"" },
                ""const"": {},
                ""enum"": {
                    ""type"": ""array"",
                    ""minItems"": 1,
                    ""uniqueItems"": true
                },
                ""type"": {
                    ""anyOf"": [
                        { ""$ref"": ""#/definitions/simpleTypes"" },
                        {
                            ""type"": ""array"",
                            ""items"": { ""$ref"": ""#/definitions/simpleTypes"" },
                            ""minItems"": 1,
                            ""uniqueItems"": true
                        }
                    ]
                },
                ""format"": { ""type"": ""string"" },
                ""allOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""anyOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""oneOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""not"": { ""$ref"": ""#"" }
            },
            ""default"": {}
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""http://json-schema.org/draft-07/schema#"",
            ""$id"": ""http://json-schema.org/draft-07/schema#"",
            ""title"": ""Core schema meta-schema"",
            ""definitions"": {
                ""schemaArray"": {
                    ""type"": ""array"",
                    ""minItems"": 1,
                    ""items"": { ""$ref"": ""#"" }
                },
                ""nonNegativeInteger"": {
                    ""type"": ""integer"",
                    ""minimum"": 0
                },
                ""nonNegativeIntegerDefault0"": {
                    ""allOf"": [
                        { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                        { ""default"": 0 }
                    ]
                },
                ""simpleTypes"": {
                    ""enum"": [
                        ""array"",
                        ""boolean"",
                        ""integer"",
                        ""null"",
                        ""number"",
                        ""object"",
                        ""string""
                    ]
                },
                ""stringArray"": {
                    ""type"": ""array"",
                    ""items"": { ""type"": ""string"" },
                    ""uniqueItems"": true,
                    ""default"": []
                }
            },
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""$id"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference""
                },
                ""$schema"": {
                    ""type"": ""string"",
                    ""format"": ""uri""
                },
                ""$ref"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference""
                },
                ""$comment"": {
                    ""type"": ""string""
                },
                ""title"": {
                    ""type"": ""string""
                },
                ""description"": {
                    ""type"": ""string""
                },
                ""default"": true,
                ""readOnly"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""writeOnly"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""examples"": {
                    ""type"": ""array"",
                    ""items"": true
                },
                ""multipleOf"": {
                    ""type"": ""number"",
                    ""exclusiveMinimum"": 0
                },
                ""maximum"": {
                    ""type"": ""number""
                },
                ""exclusiveMaximum"": {
                    ""type"": ""number""
                },
                ""minimum"": {
                    ""type"": ""number""
                },
                ""exclusiveMinimum"": {
                    ""type"": ""number""
                },
                ""maxLength"": { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                ""minLength"": { ""$ref"": ""#/definitions/nonNegativeIntegerDefault0"" },
                ""pattern"": {
                    ""type"": ""string"",
                    ""format"": ""regex""
                },
                ""additionalItems"": { ""$ref"": ""#"" },
                ""items"": {
                    ""anyOf"": [
                        { ""$ref"": ""#"" },
                        { ""$ref"": ""#/definitions/schemaArray"" }
                    ],
                    ""default"": true
                },
                ""maxItems"": { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                ""minItems"": { ""$ref"": ""#/definitions/nonNegativeIntegerDefault0"" },
                ""uniqueItems"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""contains"": { ""$ref"": ""#"" },
                ""maxProperties"": { ""$ref"": ""#/definitions/nonNegativeInteger"" },
                ""minProperties"": { ""$ref"": ""#/definitions/nonNegativeIntegerDefault0"" },
                ""required"": { ""$ref"": ""#/definitions/stringArray"" },
                ""additionalProperties"": { ""$ref"": ""#"" },
                ""definitions"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""default"": {}
                },
                ""properties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""default"": {}
                },
                ""patternProperties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$ref"": ""#"" },
                    ""propertyNames"": { ""format"": ""regex"" },
                    ""default"": {}
                },
                ""dependencies"": {
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""anyOf"": [
                            { ""$ref"": ""#"" },
                            { ""$ref"": ""#/definitions/stringArray"" }
                        ]
                    }
                },
                ""propertyNames"": { ""$ref"": ""#"" },
                ""const"": true,
                ""enum"": {
                    ""type"": ""array"",
                    ""items"": true,
                    ""minItems"": 1,
                    ""uniqueItems"": true
                },
                ""type"": {
                    ""anyOf"": [
                        { ""$ref"": ""#/definitions/simpleTypes"" },
                        {
                            ""type"": ""array"",
                            ""items"": { ""$ref"": ""#/definitions/simpleTypes"" },
                            ""minItems"": 1,
                            ""uniqueItems"": true
                        }
                    ]
                },
                ""format"": { ""type"": ""string"" },
                ""contentMediaType"": { ""type"": ""string"" },
                ""contentEncoding"": { ""type"": ""string"" },
                ""if"": { ""$ref"": ""#"" },
                ""then"": { ""$ref"": ""#"" },
                ""else"": { ""$ref"": ""#"" },
                ""allOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""anyOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""oneOf"": { ""$ref"": ""#/definitions/schemaArray"" },
                ""not"": { ""$ref"": ""#"" }
            },
            ""default"": true
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$id"": ""https://json-schema.org/draft/2019-09/meta/content"",
            ""$recursiveAnchor"": true,

            ""title"": ""Content vocabulary meta-schema"",

            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""contentMediaType"": { ""type"": ""string"" },
                ""contentEncoding"": { ""type"": ""string"" },
                ""contentSchema"": { ""$recursiveRef"": ""#"" }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$id"": ""https://json-schema.org/draft/2019-09/meta/format"",
            ""$recursiveAnchor"": true,

            ""title"": ""Format vocabulary meta-schema"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""format"": { ""type"": ""string"" }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$id"": ""https://json-schema.org/draft/2019-09/meta/meta-data"",
            ""$recursiveAnchor"": true,

            ""title"": ""Meta-data vocabulary meta-schema"",

            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""title"": {
                    ""type"": ""string""
                },
                ""description"": {
                    ""type"": ""string""
                },
                ""default"": true,
                ""deprecated"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""readOnly"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""writeOnly"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""examples"": {
                    ""type"": ""array"",
                    ""items"": true
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$id"": ""https://json-schema.org/draft/2019-09/meta/validation"",
            ""$recursiveAnchor"": true,

            ""title"": ""Validation vocabulary meta-schema"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""multipleOf"": {
                    ""type"": ""number"",
                    ""exclusiveMinimum"": 0
                },
                ""maximum"": {
                    ""type"": ""number""
                },
                ""exclusiveMaximum"": {
                    ""type"": ""number""
                },
                ""minimum"": {
                    ""type"": ""number""
                },
                ""exclusiveMinimum"": {
                    ""type"": ""number""
                },
                ""maxLength"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minLength"": { ""$ref"": ""#/$defs/nonNegativeIntegerDefault0"" },
                ""pattern"": {
                    ""type"": ""string"",
                    ""format"": ""regex""
                },
                ""maxItems"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minItems"": { ""$ref"": ""#/$defs/nonNegativeIntegerDefault0"" },
                ""uniqueItems"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""maxContains"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minContains"": {
                    ""$ref"": ""#/$defs/nonNegativeInteger"",
                    ""default"": 1
                },
                ""maxProperties"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minProperties"": { ""$ref"": ""#/$defs/nonNegativeIntegerDefault0"" },
                ""required"": { ""$ref"": ""#/$defs/stringArray"" },
                ""dependentRequired"": {
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""$ref"": ""#/$defs/stringArray""
                    }
                },
                ""const"": true,
                ""enum"": {
                    ""type"": ""array"",
                    ""items"": true
                },
                ""type"": {
                    ""anyOf"": [
                        { ""$ref"": ""#/$defs/simpleTypes"" },
                        {
                            ""type"": ""array"",
                            ""items"": { ""$ref"": ""#/$defs/simpleTypes"" },
                            ""minItems"": 1,
                            ""uniqueItems"": true
                        }
                    ]
                }
            },
            ""$defs"": {
                ""nonNegativeInteger"": {
                    ""type"": ""integer"",
                    ""minimum"": 0
                },
                ""nonNegativeIntegerDefault0"": {
                    ""$ref"": ""#/$defs/nonNegativeInteger"",
                    ""default"": 0
                },
                ""simpleTypes"": {
                    ""enum"": [
                        ""array"",
                        ""boolean"",
                        ""integer"",
                        ""null"",
                        ""number"",
                        ""object"",
                        ""string""
                    ]
                },
                ""stringArray"": {
                    ""type"": ""array"",
                    ""items"": { ""type"": ""string"" },
                    ""uniqueItems"": true,
                    ""default"": []
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$id"": ""https://json-schema.org/draft/2019-09/meta/applicator"",
            ""$recursiveAnchor"": true,

            ""title"": ""Applicator vocabulary meta-schema"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""additionalItems"": { ""$recursiveRef"": ""#"" },
                ""unevaluatedItems"": { ""$recursiveRef"": ""#"" },
                ""items"": {
                    ""anyOf"": [
                        { ""$recursiveRef"": ""#"" },
                        { ""$ref"": ""#/$defs/schemaArray"" }
                    ]
                },
                ""contains"": { ""$recursiveRef"": ""#"" },
                ""additionalProperties"": { ""$recursiveRef"": ""#"" },
                ""unevaluatedProperties"": { ""$recursiveRef"": ""#"" },
                ""properties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$recursiveRef"": ""#"" },
                    ""default"": {}
                },
                ""patternProperties"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$recursiveRef"": ""#"" },
                    ""propertyNames"": { ""format"": ""regex"" },
                    ""default"": {}
                },
                ""dependentSchemas"": {
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""$recursiveRef"": ""#""
                    }
                },
                ""propertyNames"": { ""$recursiveRef"": ""#"" },
                ""if"": { ""$recursiveRef"": ""#"" },
                ""then"": { ""$recursiveRef"": ""#"" },
                ""else"": { ""$recursiveRef"": ""#"" },
                ""allOf"": { ""$ref"": ""#/$defs/schemaArray"" },
                ""anyOf"": { ""$ref"": ""#/$defs/schemaArray"" },
                ""oneOf"": { ""$ref"": ""#/$defs/schemaArray"" },
                ""not"": { ""$recursiveRef"": ""#"" }
            },
            ""$defs"": {
                ""schemaArray"": {
                    ""type"": ""array"",
                    ""minItems"": 1,
                    ""items"": { ""$recursiveRef"": ""#"" }
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$id"": ""https://json-schema.org/draft/2019-09/meta/core"",
            ""$recursiveAnchor"": true,

            ""title"": ""Core vocabulary meta-schema"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""$id"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference"",
                    ""$comment"": ""Non-empty fragments not allowed."",
                    ""pattern"": ""^[^#]*#?$""
                },
                ""$schema"": {
                    ""type"": ""string"",
                    ""format"": ""uri""
                },
                ""$anchor"": {
                    ""type"": ""string"",
                    ""pattern"": ""^[A-Za-z][-A-Za-z0-9.:_]*$""
                },
                ""$ref"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference""
                },
                ""$recursiveRef"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference""
                },
                ""$recursiveAnchor"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""$vocabulary"": {
                    ""type"": ""object"",
                    ""propertyNames"": {
                        ""type"": ""string"",
                        ""format"": ""uri""
                    },
                    ""additionalProperties"": {
                        ""type"": ""boolean""
                    }
                },
                ""$comment"": {
                    ""type"": ""string""
                },
                ""$defs"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$recursiveRef"": ""#"" },
                    ""default"": {}
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$id"": ""https://json-schema.org/draft/2019-09/schema"",
            ""$vocabulary"": {
                ""https://json-schema.org/draft/2019-09/vocab/core"": true,
                ""https://json-schema.org/draft/2019-09/vocab/applicator"": true,
                ""https://json-schema.org/draft/2019-09/vocab/validation"": true,
                ""https://json-schema.org/draft/2019-09/vocab/meta-data"": true,
                ""https://json-schema.org/draft/2019-09/vocab/format"": false,
                ""https://json-schema.org/draft/2019-09/vocab/content"": true
            },
            ""$recursiveAnchor"": true,

            ""title"": ""Core and Validation specifications meta-schema"",
            ""allOf"": [
                {""$ref"": ""meta/core""},
                {""$ref"": ""meta/applicator""},
                {""$ref"": ""meta/validation""},
                {""$ref"": ""meta/meta-data""},
                {""$ref"": ""meta/format""},
                {""$ref"": ""meta/content""}
            ],
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""definitions"": {
                    ""$comment"": ""While no longer an official keyword as it is replaced by $defs, this keyword is retained in the meta-schema to prevent incompatible extensions as it remains in common use."",
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$recursiveRef"": ""#"" },
                    ""default"": {}
                },
                ""dependencies"": {
                    ""$comment"": ""dependencies is no longer a keyword, but schema authors should avoid redefining it to facilitate a smooth transition to dependentSchemas and dependentRequired"",
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""anyOf"": [
                            { ""$recursiveRef"": ""#"" },
                            { ""$ref"": ""meta/validation#/$defs/stringArray"" }
                        ]
                    }
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$id"": ""https://json-schema.org/draft/2020-12/meta/content"",
            ""$dynamicAnchor"": ""meta"",

            ""title"": ""Content vocabulary meta-schema"",

            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""contentEncoding"": { ""type"": ""string"" },
                ""contentMediaType"": { ""type"": ""string"" },
                ""contentSchema"": { ""$dynamicRef"": ""#meta"" }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$id"": ""https://json-schema.org/draft/2020-12/meta/format-annotation"",
            ""$dynamicAnchor"": ""meta"",

            ""title"": ""Format vocabulary meta-schema for annotation results"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""format"": { ""type"": ""string"" }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$id"": ""https://json-schema.org/draft/2020-12/meta/meta-data"",
            ""$dynamicAnchor"": ""meta"",

            ""title"": ""Meta-data vocabulary meta-schema"",

            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""title"": {
                    ""type"": ""string""
                },
                ""description"": {
                    ""type"": ""string""
                },
                ""default"": true,
                ""deprecated"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""readOnly"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""writeOnly"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""examples"": {
                    ""type"": ""array"",
                    ""items"": true
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$id"": ""https://json-schema.org/draft/2020-12/meta/validation"",
            ""$dynamicAnchor"": ""meta"",

            ""title"": ""Validation vocabulary meta-schema"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""type"": {
                    ""anyOf"": [
                        { ""$ref"": ""#/$defs/simpleTypes"" },
                        {
                            ""type"": ""array"",
                            ""items"": { ""$ref"": ""#/$defs/simpleTypes"" },
                            ""minItems"": 1,
                            ""uniqueItems"": true
                        }
                    ]
                },
                ""const"": true,
                ""enum"": {
                    ""type"": ""array"",
                    ""items"": true
                },
                ""multipleOf"": {
                    ""type"": ""number"",
                    ""exclusiveMinimum"": 0
                },
                ""maximum"": {
                    ""type"": ""number""
                },
                ""exclusiveMaximum"": {
                    ""type"": ""number""
                },
                ""minimum"": {
                    ""type"": ""number""
                },
                ""exclusiveMinimum"": {
                    ""type"": ""number""
                },
                ""maxLength"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minLength"": { ""$ref"": ""#/$defs/nonNegativeIntegerDefault0"" },
                ""pattern"": {
                    ""type"": ""string"",
                    ""format"": ""regex""
                },
                ""maxItems"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minItems"": { ""$ref"": ""#/$defs/nonNegativeIntegerDefault0"" },
                ""uniqueItems"": {
                    ""type"": ""boolean"",
                    ""default"": false
                },
                ""maxContains"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minContains"": {
                    ""$ref"": ""#/$defs/nonNegativeInteger"",
                    ""default"": 1
                },
                ""maxProperties"": { ""$ref"": ""#/$defs/nonNegativeInteger"" },
                ""minProperties"": { ""$ref"": ""#/$defs/nonNegativeIntegerDefault0"" },
                ""required"": { ""$ref"": ""#/$defs/stringArray"" },
                ""dependentRequired"": {
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""$ref"": ""#/$defs/stringArray""
                    }
                }
            },
            ""$defs"": {
                ""nonNegativeInteger"": {
                    ""type"": ""integer"",
                    ""minimum"": 0
                },
                ""nonNegativeIntegerDefault0"": {
                    ""$ref"": ""#/$defs/nonNegativeInteger"",
                    ""default"": 0
                },
                ""simpleTypes"": {
                    ""enum"": [
                        ""array"",
                        ""boolean"",
                        ""integer"",
                        ""null"",
                        ""number"",
                        ""object"",
                        ""string""
                    ]
                },
                ""stringArray"": {
                    ""type"": ""array"",
                    ""items"": { ""type"": ""string"" },
                    ""uniqueItems"": true,
                    ""default"": []
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$id"": ""https://json-schema.org/draft/2020-12/meta/unevaluated"",
            ""$dynamicAnchor"": ""meta"",

            ""title"": ""Unevaluated applicator vocabulary meta-schema"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""unevaluatedItems"": { ""$dynamicRef"": ""#meta"" },
                ""unevaluatedProperties"": { ""$dynamicRef"": ""#meta"" }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
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
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$id"": ""https://json-schema.org/draft/2020-12/meta/core"",
            ""$dynamicAnchor"": ""meta"",

            ""title"": ""Core vocabulary meta-schema"",
            ""type"": [""object"", ""boolean""],
            ""properties"": {
                ""$id"": {
                    ""$ref"": ""#/$defs/uriReferenceString"",
                    ""$comment"": ""Non-empty fragments not allowed."",
                    ""pattern"": ""^[^#]*#?$""
                },
                ""$schema"": { ""$ref"": ""#/$defs/uriString"" },
                ""$ref"": { ""$ref"": ""#/$defs/uriReferenceString"" },
                ""$anchor"": { ""$ref"": ""#/$defs/anchorString"" },
                ""$dynamicRef"": { ""$ref"": ""#/$defs/uriReferenceString"" },
                ""$dynamicAnchor"": { ""$ref"": ""#/$defs/anchorString"" },
                ""$vocabulary"": {
                    ""type"": ""object"",
                    ""propertyNames"": { ""$ref"": ""#/$defs/uriString"" },
                    ""additionalProperties"": {
                        ""type"": ""boolean""
                    }
                },
                ""$comment"": {
                    ""type"": ""string""
                },
                ""$defs"": {
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$dynamicRef"": ""#meta"" }
                }
            },
            ""$defs"": {
                ""anchorString"": {
                    ""type"": ""string"",
                    ""pattern"": ""^[A-Za-z_][-A-Za-z0-9._]*$""
                },
                ""uriString"": {
                    ""type"": ""string"",
                    ""format"": ""uri""
                },
                ""uriReferenceString"": {
                    ""type"": ""string"",
                    ""format"": ""uri-reference""
                }
            }
        }
    "));

    JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
        {
            ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$id"": ""https://json-schema.org/draft/2020-12/schema"",
            ""$vocabulary"": {
                ""https://json-schema.org/draft/2020-12/vocab/core"": true,
                ""https://json-schema.org/draft/2020-12/vocab/applicator"": true,
                ""https://json-schema.org/draft/2020-12/vocab/unevaluated"": true,
                ""https://json-schema.org/draft/2020-12/vocab/validation"": true,
                ""https://json-schema.org/draft/2020-12/vocab/meta-data"": true,
                ""https://json-schema.org/draft/2020-12/vocab/format-annotation"": true,
                ""https://json-schema.org/draft/2020-12/vocab/content"": true
            },
            ""$dynamicAnchor"": ""meta"",

            ""title"": ""Core and Validation specifications meta-schema"",
            ""allOf"": [
                {""$ref"": ""meta/core""},
                {""$ref"": ""meta/applicator""},
                {""$ref"": ""meta/unevaluated""},
                {""$ref"": ""meta/validation""},
                {""$ref"": ""meta/meta-data""},
                {""$ref"": ""meta/format-annotation""},
                {""$ref"": ""meta/content""}
            ],
            ""type"": [""object"", ""boolean""],
            ""$comment"": ""This meta-schema also defines keywords that have appeared in previous drafts in order to prevent incompatible extensions as they remain in common use."",
            ""properties"": {
                ""definitions"": {
                    ""$comment"": ""definitions has been replaced by $defs."",
                    ""type"": ""object"",
                    ""additionalProperties"": { ""$dynamicRef"": ""#meta"" },
                    ""deprecated"": true,
                    ""default"": {}
                },
                ""dependencies"": {
                    ""$comment"": ""dependencies has been split and replaced by dependentSchemas and dependentRequired in order to serve their differing semantics."",
                    ""type"": ""object"",
                    ""additionalProperties"": {
                        ""anyOf"": [
                            { ""$dynamicRef"": ""#meta"" },
                            { ""$ref"": ""meta/validation#/$defs/stringArray"" }
                        ]
                    },
                    ""deprecated"": true,
                    ""default"": {}
                },
                ""$recursiveAnchor"": {
                    ""$comment"": ""$recursiveAnchor has been replaced by $dynamicAnchor."",
                    ""$ref"": ""meta/core#/$defs/anchorString"",
                    ""deprecated"": true
                },
                ""$recursiveRef"": {
                    ""$comment"": ""$recursiveRef has been replaced by $dynamicRef."",
                    ""$ref"": ""meta/core#/$defs/uriReferenceString"",
                    ""deprecated"": true
                }
            }
        }
    "));

    if (bLoadTestSuiteFiles)
    {
        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$id"": ""http://localhost:1234/draft2020-12/detached-dynamicref.json"",
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$defs"": {
                    ""foo"": {
                        ""$dynamicRef"": ""#detached""
                    },
                    ""detached"": {
                        ""$dynamicAnchor"": ""detached"",
                        ""type"": ""integer""
                    }
                }
            }
        "));

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$id"": ""http://localhost:1234/draft2020-12/detached-ref.json"",
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$defs"": {
                    ""foo"": {
                        ""$ref"": ""#detached""
                    },
                    ""detached"": {
                        ""$anchor"": ""detached"",
                        ""type"": ""integer""
                    }
                }
            }
        "));

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""description"": ""extendible array"",
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$id"": ""http://localhost:1234/draft2020-12/extendible-dynamic-ref.json"",
                ""type"": ""object"",
                ""properties"": {
                    ""elements"": {
                        ""type"": ""array"",
                        ""items"": {
                            ""$dynamicRef"": ""#elements""
                        }
                    }
                },
                ""required"": [""elements""],
                ""additionalProperties"": false,
                ""$defs"": {
                    ""elements"": {
                        ""$dynamicAnchor"": ""elements""
                    }
                }
            }
        "));

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$id"": ""http://localhost:1234/draft2020-12/format-assertion-false.json"",
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$vocabulary"": {
                    ""https://json-schema.org/draft/2020-12/vocab/core"": true,
                    ""https://json-schema.org/draft/2020-12/vocab/format-assertion"": false
                },
                ""$dynamicAnchor"": ""meta"",
                ""allOf"": [
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/core"" },
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/format-assertion"" }
                ]
            }
        "));

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$id"": ""http://localhost:1234/draft2020-12/format-assertion-true.json"",
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$vocabulary"": {
                    ""https://json-schema.org/draft/2020-12/vocab/core"": true,
                    ""https://json-schema.org/draft/2020-12/vocab/format-assertion"": true
                },
                ""$dynamicAnchor"": ""meta"",
                ""allOf"": [
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/core"" },
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/format-assertion"" }
                ]
            }
        "));

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$id"": ""http://localhost:1234/draft2020-12/metaschema-no-validation.json"",
                ""$vocabulary"": {
                    ""https://json-schema.org/draft/2020-12/vocab/applicator"": true,
                    ""https://json-schema.org/draft/2020-12/vocab/core"": true
                },
                ""$dynamicAnchor"": ""meta"",
                ""allOf"": [
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/applicator"" },
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/core"" }
                ]
            }
        "));

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$id"": ""http://localhost:1234/draft2020-12/metaschema-optional-vocabulary.json"",
                ""$vocabulary"": {
                    ""https://json-schema.org/draft/2020-12/vocab/validation"": true,
                    ""https://json-schema.org/draft/2020-12/vocab/core"": true,
                    ""http://localhost:1234/draft/2020-12/vocab/custom"": false
                },
                ""$dynamicAnchor"": ""meta"",
                ""allOf"": [
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/validation"" },
                    { ""$ref"": ""https://json-schema.org/draft/2020-12/meta/core"" }
                ]
            }
        "));

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$id"": ""http://localhost:1234/draft2020-12/prefixItems.json"",
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""prefixItems"": [
                    {""type"": ""string""}
                ]
            }
        "));   

        JsonArrayInsertInplace(jaTrustedSchema, JsonParse(r"
            {
                ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",
                ""$id"": ""http://localhost:1234/draft2020-12/ref-and-defs.json"",
                ""$defs"": {
                    ""inner"": {
                        ""properties"": {
                            ""bar"": { ""type"": ""string"" }
                        }
                    }
                },
                ""$ref"": ""#/$defs/inner""
            }
        "));  
    }

    return jaTrustedSchema;
}
