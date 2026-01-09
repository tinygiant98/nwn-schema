The repository contains a full-featured json schema validator written entirely in nwscript.  NWNX:EE is not required to run this validator.

This validator implements full json schema validation as defined by [json-schema.org](https://json-schema.org), supporting all published json metaschema including [draft-04](https://json-schema.org/draft-05) (yes, I know it says `draft-05`, but it's `draft-04`), [draft-06](https://json-schema.org/draft-06), [draft-07](https://json-schema.org/draft-07), [draft 2019-09](https://json-schema.org/draft/2019-09) and [draft 2020-12](https://json-schema.org/draft/2020-12).  All keywords, both mandatory and optional, for each draft have been implemented.  Additionally, all [json-schema.org test suites](https://github.com/json-schema-org/JSON-Schema-Test-Suite) have been validated to return correct results, except the `refRmote` test group because it requires files that are onerous to load into the system and provides no additional insight into the validity of the validation process.

Why?  Why not.  Creation of a structured logging/audit system was halted because there was no readily-available method for json schema validation to ensure log entires were valid.  So now there's this.  I'm sure the NWNX:EE guys could spin this up with an external C++ validation libary in seconds, but here it is anyway.

Notes:
- You can be assured that ***THERE ARE LIKELY STILL PLENTY OF BUGS IN THIS SYSTEM***, so if you decide to use it, consider yourself a beta tester.  Please let me know if you find something that doesn't seem to be working correctly.
- TMI is potentially an issue for exceptionally complicated or deeply nested schema, especially those that contain multiple levels of `$ref`, `$dynamicRef` or `$recursiveRef`, but those are unlikely in most cases as they are considered advanced usage, so TMI shouldn't be too much of a threat for most use cases.
- You do not need to manually load the trusted metaschema into the database.  It will be automatically populated the first time any database-oriented function is run, including all of the `Validate*` functions detailed below.

Documentation is forthcoming, but for those that want to experiment with the system, some of the utilities from [Squatting Monk's sm-utils](https://github.com/squattingmonk/sm-utils) repo are required.

Beyond those, the only required validation system files are `util_c_schema` and `util_i_schema`.  The file `schema_p_core` is an experimental plugin designed to be used under [Squatting Monk's NWN-Core-Framework](https://github.com/squattingmonk/nwn-core-framework), and only exists for testing purposes.  It is not required for normal system usage.

- `util_c_schema` is a configuration file for the system where users can specify where persistent data will be stored and, if necessary, update the trusted metaschema source.  The default metaschema can also be defined here, as well as all trusted metaschema, however, modification of these values may lead to unintended consequences during system operation.

- `util_i_schema` is the primary utility file and is the file that should be `#include`d in other files for proper system operation.  This is a monolithic file designed to eventually be packaged into a utility system, so there are no additional includes beyond the associated configuration file.  Yes, there's a lot of code in here.  So what?  It's doing something difficult, so let it be and stop whining.

There are four public functions that users can use to interface with the system.  Full remarks for these functions can be found in the `Public Function Prototypes` section of `util_i_schema` as well as below this paragraph.
- `ValidateSchema(json joSchema, int bSaveIfValid = TRUE)`: This function will allow users to validate a custom schema against its designated metaschema or, if missing, against the default metaschema.  If `joSchema` is validated successfully, it can optionally be saved into the schema database for future use, assuming `joSchema` contains an `$id`.  This function will return an integer representing TRUE or FALSE.
- `ValidateInstance(json jInstance, string sSchema)`: This function will allow users to validate a json instance against a previously validated schema.  `sSchema` should be the `$id` value of the schema to validate `jInstance` against.  If `sSchema` cannot be found in the schema database, validation will fail.  This function will return an integer representing TRUE or FALSE.
- `ValidateInstanceAdHoc(json jInstance, json joSchema)`: This function will allow users to validate a json instance against any valid schema object.  If `joSchema` contains an `$id`, the system will attempt to find that schema in the schema database to short-cut the validation process.  If `joSchema` does not have an `$id` or is not found in the schema database, it will be validated against its metaschema (if defined) or the default metaschema to ensure the schema itself is valid.  If the schema is found to be valid (either through database retrieval or validation), it will then be used to validate `jInstance`.  This function will return an integer representing TRUE or FALSE.
- `GetValidationResult(int nVerbosityLevel = SCHEMA_OUTPUT_LEVEL_VERBOSE)`: This function will allow users to retrieve the full validation result at the verbose level of output.  Other levels are available, as defined by [json-schema.org](https://json-schema.org), but have not been tested as part of the public API yet, so results may vary.  The returned json object will be a deeply-nested outputUnit containing visitation details for each node in the valiation schema that applies to the passed instance.  This value is only available immediately after the validation is complete.  The behavior of the system if retrieving the value at a later time is UNDEFINED.

```c
/// -----------------------------------------------------------------------------------------------
///                                  PUBLIC FUNCTION PROTOTYPES
/// -----------------------------------------------------------------------------------------------

/// @brief Validate a schema against the schema's designated metaschema and, optionally, save the
///     schema to the schema database if validation passes.
/// @param joSchema Schema to validate.
/// @param bSaveIfValid TRUE to save the schema to the database, if valid.
/// @note If joSchema does not have a $schema key, or the referenced $schema cannot be resolved,
///     the default metaschema will be used, which is normally the most recent metaschema draft
///     from json-schema.org.
int ValidateSchema(json joSchema, int bSaveIfValid = TRUE);

/// @brief Validate an instance against a specific schema.
/// @param jInstance Instance to validate.
/// @param sSchema $id of schema to validate instance against.
/// @note Since instances generally do not carry $schema keys, if sSchema is an empty string or
///     the schema identified by sSchema cannot be found in the database, the validation will fail.
int ValidateInstance(json jInstance, string sSchema);

/// @brief Validate an instance against a schema.
/// @param jInstance Instance to validate.
/// @param joSchema Schema to validate instance against.
/// @note If joSchema contains an $id, the system will first attempt to retrieve a previously-
///     validated schema from the schema database.  If not found, the system will first attempt
///     to validate joSchema against its designated metaschema and, if found to be valid, will
///     then validate jInstance against joSchema.
/// @note If joSchema is unknown to the schema system, successfully validates against its
///     designated metaschema, and contains a unique $id, joSchema will be saved to the schema
///     database for future use.
int ValidateInstanceAdHoc(json jInstance, json joSchema);

const int SCHEMA_OUTPUT_LEVEL_VERBOSE = 0;
const int SCHEMA_OUTPUT_LEVEL_DETAILED = 1;
const int SCHEMA_OUTPUT_LEVEL_BASIC = 2;
const int SCHEMA_OUTPUT_LEVEL_FLAG = 3;

/// @brief Retrieve the validation result at the desired verbosity level.
/// @param nVerbosityLevel SCHEMA_OUTPUT_LEVEL_*.
/// @note Available verbosity levels:
///     - Verbose (default): Provides validation information in an uncondensed hierarchical
///         structure that matches the exact structure of the validating schema.
///     - Detailed: Provides validation information in a condensed hierachical structure based
///         on the structure of the validating schema.
///     - Basic: Provides validation information in a flat list structure.
///     - Flag: Provides a boolean value which simply indicates the overall validation result
///         with no additional details.
/// @note Invalid values for nVerbosityLevel will result in default of SCHEMA_OUTPUT_LEVEL_VERBOSE.
json GetValidationResult(int nVerbosityLevel = SCHEMA_OUTPUT_LEVEL_VERBOSE);
```