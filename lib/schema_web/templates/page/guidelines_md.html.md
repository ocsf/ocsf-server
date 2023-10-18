
The Open Cybersecurity Schema Framework (OCSF) guidelines and conventions.

## Attribute Levels
The event schema defines *Core*, *Optional*, and *Reserved* attributes.

*Core Attributes*
Attributes that are most common across all use cases are defined as core attributes. The core attributes are marked as **Required** or **Recommended**.

*Optional Attributes*
Optional attributes may apply to more narrow use cases, or may be more open to interpretation depending on the use case. The optional attributes are marked as **Optional**.

## Guidelines for attribute names
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

## Extending the Schema
The Open Cybersecurity Schema Framework can be extended by adding new attributes, objects, and event classes.

To extend the schema, create a new directory with same structure the top level schema directory. 
The directory may contain the following optional files and subdirectories.

|             |           |
| ----------- | --------- |
| **categories.json** | Create it to define a new event category to reserve a range of class IDs. |
| **dictionary.json** | Create it to define new attributes.    |
| **events/**          | Create it to define new event classes. |
| **objects/**         | Create it to define new objects.       |
