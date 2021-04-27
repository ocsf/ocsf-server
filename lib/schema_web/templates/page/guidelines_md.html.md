## Guidelines and Conventions
The Splunk Event Schema (SES) guidelines and conventions.

### Attribute Levels
The event schema defines *Core* and *Optional* attributes.

*Core Attributes*
Attributes that are most common across all use cases are defined as core attributes. The Core Attributes are marked as **Required**, **Reserved**, or **Recommended**.

*Optional Attributes*
Optional attributes may apply to more narrow use cases, or may be more open to interpretation depending on the use case. The Optional attributes are marked as **Optional**.

### Guidelines for attribute names
- Attribute names must be a valid UTF-8 sequence.

- Attribute names must be all lower case.

- Combine words using underscore.

- No special characters except underscore.

- Use present tense unless the attribute describes historical information.

- Use singular and plural names properly to reflect the field content.

  For example, use `events_per_sec` rather than `event_per_sec`.

- When attribute represents multiple entities, the attribute name should be pluralized and the value type should be an array.

  Example: `process.loaded_modules` includes multiple values -- a loaded module names list.

- Avoid repetition of words.

  Example: `host.host_ip` should be `host.ip`.

- Avoid abbreviations when possible.

  Some exceptions can be made for well-accepted abbreviation. Example: `ip`, or names such as `os`, `geo`.

### Extending the Schema
The Splunk Event Schema can be extended by adding new attributes, objects, and event classes.

To extend the schema create a new directory in the `schema/extensions` directory. The directory structure is the same as the top level schema directory and it may contain the following files and subdirectories:

|             |           |
| ----------- | --------- |
| **categories.json** | Create it to define a new event category to reserve a range of class IDs. |
| **dictionary.json** | Create it to define new attributes.    |
| **events/**          | Create it to define new event classes. |
| **objects/**         | Create it to define new objects.       |
