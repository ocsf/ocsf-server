# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Validator2 do
  @moduledoc """
  OCSF Event validator, version 2.
  """

  # Implementation note:
  # All of the validate_* and add_* functions take a response and return one, possibly updated.
  # The overall flow is to examine the event or list of events, and return a validation response.

  require Logger

  @spec validate(map() | list()) :: map() | list(map())
  def validate(data) when is_map(data), do: validate_event(data, Schema.dictionary())
  def validate(data) when is_list(data), do: validate_events(data, Schema.dictionary())

  @spec validate_event(map(), map()) :: map()
  defp validate_event(event, dictionary) do
    response = new_response(event)

    {response, class} = validate_class_uid_and_return_class(response, event)

    response =
      if class do
        {response, profiles} = validate_and_return_profiles(response, event)
        validate_event_against_class(response, event, class, profiles, dictionary)
      else
        # Can't continue if we can't find the class
        response
      end

    finalize_response(response)
  end

  @spec validate_events(list(map()), map()) :: list(map())
  defp validate_events(events, dictionary) do
    Enum.map(events, fn event -> validate_event(event, dictionary) end)
  end

  @spec validate_class_uid_and_return_class(map(), map()) :: {map(), nil | map()}
  defp validate_class_uid_and_return_class(response, event) do
    if Map.has_key?(event, "class_uid") do
      class_uid = event["class_uid"]

      cond do
        is_integer_t(class_uid) ->
          case Schema.find_class(class_uid) do
            nil ->
              {
                add_error(
                  response,
                  "class_uid_unknown",
                  "Unknown \"class_uid\" value; no class is defined for #{class_uid}.",
                  %{attribute_path: "class_uid", attribute: "class_uid", value: class_uid}
                ),
                nil
              }

            class ->
              {response, class}
          end

        true ->
          {
            # We need to add error here; no further validation will occur (nil returned for class).
            add_error_wrong_type(response, "class_uid", "class_uid", class_uid, "integer_t"),
            nil
          }
      end
    else
      # We need to add error here; no further validation will occur (nil returned for class).
      {add_error_required_attribute_missing(response, "class_uid", "class_uid"), nil}
    end
  end

  # This _must_ return no profiles as an empty list,
  # otherwise Schema.Utils.apply_profiles will return the wrong result (grrr).
  # This is because the API profile parameter acts as follows:
  #   * Missing parameter means "include all profiles".
  #   * Parameter with list of profiles, including no profiles (empty list) means include only
  #     these specific profiles.
  @spec validate_and_return_profiles(map(), map()) :: {map(), list(String.t())}
  defp validate_and_return_profiles(response, event) do
    metadata = event["metadata"]

    if is_map(metadata) do
      profiles = metadata["profiles"]

      cond do
        is_list(profiles) ->
          # Ensure each profile is actually defined
          schema_profiles = MapSet.new(Map.keys(Schema.profiles()))

          {response, _} =
            Enum.reduce(
              profiles,
              {response, 0},
              fn profile, {response, index} ->
                response =
                  if is_binary(profile) and not MapSet.member?(schema_profiles, profile) do
                    attribute_path = make_attribute_path_array_element("metadata.profile", index)

                    add_error(
                      response,
                      "profile_unknown",
                      "Unknown profile at \"#{attribute_path}\";" <>
                        " no profile is defined for \"#{profile}\".",
                      %{attribute_path: attribute_path, attribute: "profiles", value: profile}
                    )
                  else
                    # Either profile is wrong type (which will be caught later)
                    # or this is a known profile
                    response
                  end

                {response, index + 1}
              end
            )

          {response, profiles}

        profiles == nil ->
          # profiles are missing or null, so return []
          {response, []}

        true ->
          # profiles are the wrong type, this will be caught later, so for now just return []
          {response, []}
      end
    else
      # metadata is missing or not a map (this will become an error), so return []
      {response, []}
    end
  end

  @spec validate_event_against_class(map(), map(), map(), list(String.t()), map()) :: map()
  defp validate_event_against_class(response, event, class, profiles, dictionary) do
    response
    |> validate_class_deprecated(class)
    |> validate_attributes(event, nil, class, profiles, dictionary)
    |> validate_version(event)
    |> validate_type_uid(event)
    |> validate_constraints(event, class)
  end

  @spec validate_class_deprecated(map(), map()) :: map()
  defp validate_class_deprecated(response, class) do
    if Map.has_key?(class, :"@deprecated") do
      add_warning_class_deprecated(response, class)
    else
      response
    end
  end

  @spec validate_version(map(), map()) :: map()
  defp validate_version(response, event) do
    metadata = event["metadata"]

    if is_map(metadata) do
      version = metadata["version"]

      if is_binary(version) do
        schema_version = Schema.version()

        if version != schema_version do
          add_error(
            response,
            "version_incorrect",
            "Incorrect version at \"metadata.version\"; value of \"#{version}\"" <>
              " does not match schema version \"#{schema_version}\"." <>
              " This can also result in incorrect and/or missing validation messages.",
            %{
              attribute_path: "metadata.version",
              attribute: "version",
              value: version,
              expected_value: schema_version
            }
          )
        else
          response
        end
      else
        response
      end
    else
      response
    end
  end

  @spec validate_type_uid(map(), map()) :: map()
  defp validate_type_uid(response, event) do
    class_uid = event["class_uid"]
    activity_id = event["activity_id"]
    type_uid = event["type_uid"]

    if is_integer(class_uid) and is_integer(activity_id) and is_integer(type_uid) do
      expected_type_uid = class_uid * 100 + activity_id

      if type_uid == expected_type_uid do
        response
      else
        add_error(
          response,
          "type_uid_incorrect",
          "Event's \"type_uid\" value of #{type_uid}" <>
            " does not match expected value of #{expected_type_uid}" <>
            " (class_uid #{class_uid} * 100 + activity_id #{activity_id} = #{expected_type_uid}).",
          %{
            attribute_path: "type_uid",
            attribute: "type_uid",
            value: type_uid,
            expected_value: expected_type_uid
          }
        )
      end
    else
      # One or more of the values is missing or the wrong type, which is caught elsewhere
      response
    end
  end

  @spec validate_constraints(map(), map(), map(), nil | String.t()) :: map()
  defp validate_constraints(response, event_item, schema_item, attribute_path \\ nil) do
    if Map.has_key?(schema_item, :constraints) do
      Enum.reduce(
        schema_item[:constraints],
        response,
        fn {constraint_key, constraint_details}, response ->
          case constraint_key do
            :at_least_one ->
              # constraint_details is a list of keys where at least one must exist
              if Enum.any?(constraint_details, fn key -> Map.has_key?(event_item, key) end) do
                response
              else
                {description, extra} =
                  constraint_info(schema_item, attribute_path, constraint_key, constraint_details)

                add_error(
                  response,
                  "constraint_failed",
                  "Constraint failed: #{description};" <>
                    " expected at least one constraint attribute, bot got none.",
                  extra
                )
              end

            :just_one ->
              # constraint_details is a list of keys where exactly one must exist
              count =
                Enum.reduce(
                  constraint_details,
                  0,
                  fn key, count ->
                    if Map.has_key?(event_item, key), do: count + 1, else: count
                  end
                )

              if count == 1 do
                response
              else
                {description, extra} =
                  constraint_info(schema_item, attribute_path, constraint_key, constraint_details)

                Map.put(extra, :value_count, count)

                add_error(
                  response,
                  "constraint_failed",
                  "Constraint failed: #{description};" <>
                    " expected exactly 1 constraint attribute, got #{count}.",
                  extra
                )
              end

            _ ->
              # This could be a new kind of constraint that this code needs to start handling,
              # or this a private schema / private extension has an unknown constraint type,
              # or its a typo in a private schema / private extension.
              {description, extra} =
                constraint_info(schema_item, attribute_path, constraint_key, constraint_details)

              Logger.warning("SCHEMA BUG: Unknown constraint #{description}")

              add_error(
                response,
                "constraint_unknown",
                "SCHEMA BUG: Unknown constraint #{description}.",
                extra
              )
          end
        end
      )
    else
      response
    end
  end

  # Helper to return class or object description and extra map
  @spec constraint_info(map(), String.t(), atom(), list[String.t()]) :: {String.t(), map()}
  defp constraint_info(schema_item, attribute_path, constraint_key, constraint_details) do
    if attribute_path do
      # attribute_path exists (is not nil) for objects
      {
        "\"#{constraint_key}\" from object \"#{schema_item[:name]}\" at \"#{attribute_path}\"",
        %{
          attribute_path: attribute_path,
          constraint: %{constraint_key => constraint_details},
          object_name: schema_item[:name]
        }
      }
    else
      {
        "\"#{constraint_key}\" from class \"#{schema_item[:name]}\" uid #{schema_item[:uid]}",
        %{
          constraint: %{constraint_key => constraint_details},
          class_uid: schema_item[:uid],
          class_name: schema_item[:name]
        }
      }
    end
  end

  # Validates attributes of event or object (event_item parameter)
  # against schema's class or object (schema_item parameter).
  @spec validate_attributes(
          map(),
          map(),
          nil | String.t(),
          map(),
          list(String.t()),
          map()
        ) :: map()
  defp validate_attributes(
         response,
         event_item,
         parent_attribute_path,
         schema_item,
         profiles,
         dictionary
       ) do
    schema_attributes = Schema.Utils.apply_profiles(schema_item[:attributes], profiles)

    response
    |> validate_attributes_types(
      event_item,
      parent_attribute_path,
      schema_attributes,
      profiles,
      dictionary
    )
    |> validate_attributes_event_item_keys(
      event_item,
      parent_attribute_path,
      schema_item,
      schema_attributes
    )
    |> validate_attributes_enums(event_item, parent_attribute_path, schema_attributes)
  end

  # Validate unknown attributes
  # Scan event_item's attributes making sure each exists in schema_item's attributes
  @spec validate_attributes_types(
          map(),
          map(),
          nil | String.t(),
          list(tuple()),
          list(String.t()),
          map()
        ) :: map()
  defp validate_attributes_types(
         response,
         event_item,
         parent_attribute_path,
         schema_attributes,
         profiles,
         dictionary
       ) do
    Enum.reduce(
      schema_attributes,
      response,
      fn {attribute_key, attribute_details}, response ->
        attribute_name = Atom.to_string(attribute_key)
        attribute_path = make_attribute_path(parent_attribute_path, attribute_name)
        value = event_item[attribute_name]

        validate_attribute(
          response,
          value,
          attribute_path,
          attribute_name,
          attribute_details,
          profiles,
          dictionary
        )
      end
    )
  end

  @spec validate_attributes_event_item_keys(
          map(),
          map(),
          nil | String.t(),
          map(),
          list(tuple())
        ) :: map()
  defp validate_attributes_event_item_keys(
         response,
         event_item,
         parent_attribute_path,
         schema_item,
         schema_attributes
       ) do
    Enum.reduce(
      Map.keys(event_item),
      response,
      fn key, response ->
        if has_attribute?(schema_attributes, key) do
          response
        else
          attribute_path = make_attribute_path(parent_attribute_path, key)

          {struct_desc, extra} =
            if Map.has_key?(schema_item, :uid) do
              {
                "class \"#{schema_item[:name]}\", uid #{schema_item[:uid]}",
                %{
                  attribute_path: attribute_path,
                  attribute: key,
                  class_uid: schema_item[:uid],
                  class_name: schema_item[:name]
                }
              }
            else
              {
                "object \"#{schema_item[:name]}\"",
                %{
                  attribute_path: attribute_path,
                  attribute: key,
                  object_name: schema_item[:name]
                }
              }
            end

          add_error(
            response,
            "attribute_unknown",
            "Unknown attribute at \"#{attribute_path}\";" <>
              " attribute \"#{key}\" is not defined in #{struct_desc}.",
            extra
          )
        end
      end
    )
  end

  @spec has_attribute?(list(tuple()), String.t()) :: boolean()
  defp has_attribute?(attributes, name) do
    key = String.to_atom(name)
    Enum.any?(attributes, fn {attribute_key, _} -> attribute_key == key end)
  end

  @spec validate_attributes_enums(map(), map(), nil | String.t(), list(tuple())) :: map()
  defp validate_attributes_enums(response, event_item, parent_attribute_path, schema_attributes) do
    enum_attributes = Enum.filter(schema_attributes, fn {_ak, ad} -> Map.has_key?(ad, :enum) end)

    Enum.reduce(
      enum_attributes,
      response,
      fn {attribute_key, attribute_details}, response ->
        attribute_name = Atom.to_string(attribute_key)

        if Map.has_key?(event_item, attribute_name) do
          # The enum values are always strings, so rather than use elaborate conversions,
          # we just use Kernel.to_string/1. (The value is type checked elsewhere anyway.)
          value = event_item[attribute_name]
          value_str = to_string(value)
          value_atom = String.to_atom(value_str)

          if Map.has_key?(attribute_details[:enum], value_atom) do
            # The enum value is good - check sibling
            validate_enum_sibling(
              response,
              event_item,
              parent_attribute_path,
              value,
              value_atom,
              attribute_name,
              attribute_details
            )
          else
            attribute_path = make_attribute_path(parent_attribute_path, attribute_name)

            add_error(
              response,
              "attribute_enum_value_unknown",
              "Unknown enum value at \"#{attribute_path}\";" <>
                " value #{inspect(value)} is not defined for enum \"#{attribute_name}\".",
              %{
                attribute_path: attribute_path,
                attribute: attribute_name,
                value: value
              }
            )
          end
        else
          response
        end
      end
    )
  end

  @spec validate_enum_sibling(
          map(),
          map(),
          nil | String.t(),
          any(),
          atom(),
          String.t(),
          map()
        ) :: map()
  defp validate_enum_sibling(
         response,
         event_item,
         parent_attribute_path,
         event_enum_value,
         event_enum_value_atom,
         attribute_name,
         attribute_details
       ) do
    if event_enum_value == 99 do
      # Enum value is the integer 99 (Other). The enum sibling, if present, can be anything.
      response
    else
      sibling_name = attribute_details[:sibling]

      if Map.has_key?(event_item, sibling_name) do
        # Sibling is present - make sure the string value matches up
        enum_caption = attribute_details[:enum][event_enum_value_atom][:caption]
        sibling_value = event_item[sibling_name]

        if enum_caption == sibling_value do
          # Sibling has correct value
          response
        else
          enum_attribute_path = make_attribute_path(parent_attribute_path, attribute_name)
          sibling_attribute_path = make_attribute_path(parent_attribute_path, sibling_name)

          add_error(
            response,
            "attribute_enum_sibling_incorrect",
            "Attribute \"#{sibling_attribute_path}\" enum sibling value" <>
              " #{inspect(sibling_value)} is incorrect for" <>
              " enum \"#{enum_attribute_path}\" value #{inspect(event_enum_value)};" <>
              " expected \"#{enum_caption}\", got #{inspect(sibling_value)}.",
            %{
              attribute_path: sibling_attribute_path,
              attribute: sibling_name,
              value: sibling_value,
              expected_value: enum_caption
            }
          )
        end
      else
        # Sibling not present, which is OK
        response
      end
    end
  end

  @spec validate_attribute(
          map(),
          any(),
          String.t(),
          String.t(),
          map(),
          list(String.t()),
          map()
        ) :: map()
  defp validate_attribute(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_details,
         profiles,
         dictionary
       ) do
    if value == nil do
      validate_requirement(response, attribute_path, attribute_name, attribute_details)
    else
      response =
        validate_attribute_deprecated(
          response,
          attribute_path,
          attribute_name,
          attribute_details
        )

      # Check event_item attribute value type
      attribute_type_key = String.to_atom(attribute_details[:type])

      if attribute_type_key == :object_t or
           Map.has_key?(dictionary[:types][:attributes], attribute_type_key) do
        if attribute_details[:is_array] do
          validate_array(
            response,
            value,
            attribute_path,
            attribute_name,
            attribute_details,
            profiles,
            dictionary
          )
        else
          validate_value(
            response,
            value,
            attribute_path,
            attribute_name,
            attribute_details,
            profiles,
            dictionary
          )
        end
      else
        # This should never happen for published schemas (validator will catch this) but
        # _could_ happen for a schema that's in development and presumably running on a
        # local / private OCSF Server instance.
        Logger.warning(
          "SCHEMA BUG: Type \"#{attribute_type_key}\" is not defined in dictionary" <>
            " at attribute path \"#{attribute_path}\""
        )

        add_error(
          response,
          "schema_bug_type_missing",
          "SCHEMA BUG: Type \"#{attribute_type_key}\" is not defined in dictionary.",
          %{
            attribute_path: attribute_path,
            attribute: attribute_name,
            type: attribute_type_key,
            value: value
          }
        )
      end
    end
  end

  defp validate_requirement(response, attribute_path, attribute_name, attribute_details) do
    case attribute_details[:requirement] do
      "required" ->
        add_error_required_attribute_missing(response, attribute_path, attribute_name)

      "recommended" ->
        add_warning_recommended_attribute_missing(response, attribute_path, attribute_name)

      _ ->
        response
    end
  end

  # validate an attribute whose value should be an array (is_array: true)
  @spec validate_array(map(), any(), String.t(), String.t(), map(), list(String.t()), map()) ::
          map()
  defp validate_array(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_details,
         profiles,
         dictionary
       ) do
    if is_list(value) do
      {response, _} =
        Enum.reduce(
          value,
          {response, 0},
          fn element_value, {response, index} ->
            {
              validate_value(
                response,
                element_value,
                make_attribute_path_array_element(attribute_path, index),
                attribute_name,
                attribute_details,
                profiles,
                dictionary
              ),
              index + 1
            }
          end
        )

      response
    else
      add_error_wrong_type(
        response,
        attribute_path,
        attribute_name,
        value,
        "array of #{attribute_details[:type]}"
      )
    end
  end

  # validate a single value or element of an array (attribute with is_array: true)
  @spec validate_value(
          map(),
          any(),
          String.t(),
          String.t(),
          map(),
          list(String.t()),
          map()
        ) :: map()
  defp validate_value(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_details,
         profiles,
         dictionary
       ) do
    attribute_type = attribute_details[:type]

    if attribute_type == "object_t" do
      # object_t is a marker added by the schema compile to make it easy to check if attribute
      # is an OCSF object (otherwise we would need to notice that the attribute type isn't a
      # data dictionary type)
      object_type = attribute_details[:object_type]

      if is_map(value) do
        # Drill in to object
        validate_map_against_object(
          response,
          value,
          attribute_path,
          attribute_name,
          Schema.object(object_type),
          profiles,
          dictionary
        )
      else
        add_error_wrong_type(
          response,
          attribute_path,
          attribute_name,
          value,
          "#{object_type} (object)"
        )
      end
    else
      validate_value_against_dictionary_type(
        response,
        value,
        attribute_path,
        attribute_name,
        attribute_details,
        dictionary
      )
    end
  end

  @spec validate_map_against_object(
          map(),
          map(),
          String.t(),
          String.t(),
          map(),
          list(String.t()),
          map()
        ) :: map()
  defp validate_map_against_object(
         response,
         event_object,
         attribute_path,
         attribute_name,
         schema_object,
         profiles,
         dictionary
       ) do
    response
    |> validate_object_deprecated(attribute_path, attribute_name, schema_object)
    |> validate_attributes(event_object, attribute_path, schema_object, profiles, dictionary)
    |> validate_constraints(event_object, schema_object, attribute_path)
  end

  @spec validate_object_deprecated(map(), String.t(), String.t(), map()) :: map()
  defp validate_object_deprecated(response, attribute_path, attribute_name, schema_object) do
    if Map.has_key?(schema_object, :"@deprecated") do
      add_warning_object_deprecated(response, attribute_path, attribute_name, schema_object)
    else
      response
    end
  end

  @spec validate_value_against_dictionary_type(
          map(),
          any(),
          String.t(),
          String.t(),
          map(),
          map()
        ) :: map()
  defp validate_value_against_dictionary_type(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_details,
         dictionary
       ) do
    attribute_type_key = String.to_atom(attribute_details[:type])
    dictionary_types = dictionary[:types][:attributes]
    dictionary_type = dictionary_types[attribute_type_key]

    {primitive_type, expected_type, expected_type_extra} =
      if Map.has_key?(dictionary_type, :type) do
        # This is a subtype (e.g., username_t, a subtype of string_t)
        primitive_type = String.to_atom(dictionary_type[:type])
        {primitive_type, attribute_type_key, " (#{primitive_type})"}
      else
        # This is a primitive type
        {attribute_type_key, attribute_type_key, ""}
      end

    case primitive_type do
      :boolean_t ->
        if is_boolean(value) do
          validate_type_values(
            response,
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
        else
          add_error_wrong_type(
            response,
            attribute_path,
            attribute_name,
            value,
            expected_type,
            expected_type_extra
          )
        end

      :float_t ->
        if is_float(value) do
          response
          |> validate_number_range(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
          |> validate_type_values(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
        else
          add_error_wrong_type(
            response,
            attribute_path,
            attribute_name,
            value,
            expected_type,
            expected_type_extra
          )
        end

      :integer_t ->
        if is_integer_t(value) do
          response
          |> validate_number_range(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
          |> validate_type_values(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
        else
          add_error_wrong_type(
            response,
            attribute_path,
            attribute_name,
            value,
            expected_type,
            expected_type_extra
          )
        end

      :json_t ->
        response

      :long_t ->
        if is_long_t(value) do
          response
          |> validate_number_range(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
          |> validate_type_values(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
        else
          add_error_wrong_type(
            response,
            attribute_path,
            attribute_name,
            value,
            expected_type,
            expected_type_extra
          )
        end

      :string_t ->
        if is_binary(value) do
          response
          |> validate_string_max_len(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
          |> validate_string_regex(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
          |> validate_type_values(
            value,
            attribute_path,
            attribute_name,
            attribute_type_key,
            dictionary_types
          )
        else
          add_error_wrong_type(
            response,
            attribute_path,
            attribute_name,
            value,
            expected_type,
            expected_type_extra
          )
        end

      _ ->
        # Unhandled type (schema bug)
        # This should never happen for published schemas (ocsf-validator catches this) but
        # _could_ happen for a schema that's in development or with a private extension,
        # and presumably running on a local / private OCSF Server instance.
        Logger.warning(
          "SCHEMA BUG: Unknown primitive type \"#{primitive_type}\"" <>
            " at attribute path \"#{attribute_path}\""
        )

        add_error(
          response,
          "schema_bug_primitive_type_unknown",
          "SCHEMA BUG: Unknown primitive type \"#{primitive_type}\".",
          %{
            attribute_path: attribute_path,
            attribute: attribute_name,
            type: attribute_type_key,
            value: value
          }
        )
    end
  end

  @spec validate_type_values(
          map(),
          any(),
          String.t(),
          String.t(),
          atom(),
          map()
        ) :: map()
  defp validate_type_values(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_type_key,
         dictionary_types
       ) do
    dictionary_type = dictionary_types[attribute_type_key]

    cond do
      Map.has_key?(dictionary_type, :values) ->
        # This is a primitive type or subtype with :values
        values = dictionary_type[:values]

        if Enum.any?(values, fn v -> value == v end) do
          response
        else
          add_error(
            response,
            "attribute_value_not_in_type_values",
            "Attribute \"#{attribute_path}\" value" <>
              " is not in type \"#{attribute_type_key}\" list of allowed values.",
            %{
              attribute_path: attribute_path,
              attribute: attribute_name,
              type: attribute_type_key,
              value: value,
              allowed_values: values
            }
          )
        end

      Map.has_key?(dictionary_type, :type) ->
        # This is a subtype, so check super type
        super_type_key = String.to_atom(dictionary_type[:type])
        super_type = dictionary_types[super_type_key]

        if Map.has_key?(super_type, :values) do
          values = super_type[:values]

          if Enum.any?(values, fn v -> value == v end) do
            response
          else
            add_error(
              response,
              "attribute_value_not_in_super_type_values",
              "Attribute \"#{attribute_path}\", type \"#{attribute_type_key}\"," <>
                " value is not in super type \"#{super_type_key}\" list of allowed values.",
              %{
                attribute_path: attribute_path,
                attribute: attribute_name,
                super_type: super_type_key,
                type: attribute_type_key,
                value: value,
                allowed_values: values
              }
            )
          end
        else
          response
        end

      true ->
        response
    end
  end

  # Validate a number against a possible range constraint.
  # If attribute_type_key refers to a subtype, the subtype is checked first, and if the subtype
  # doesn't have a range, the supertype is checked.
  @spec validate_number_range(
          map(),
          float() | integer(),
          String.t(),
          String.t(),
          atom(),
          map()
        ) :: map()
  defp validate_number_range(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_type_key,
         dictionary_types
       ) do
    dictionary_type = dictionary_types[attribute_type_key]

    cond do
      Map.has_key?(dictionary_type, :range) ->
        # This is a primitive type or subtype with a range
        [low, high] = dictionary_type[:range]

        if value < low or value > high do
          add_error(
            response,
            "attribute_value_exceeds_range",
            "Attribute \"#{attribute_path}\" value" <>
              " is outside type \"#{attribute_type_key}\" range of #{low} to #{high}.",
            %{
              attribute_path: attribute_path,
              attribute: attribute_name,
              type: attribute_type_key,
              value: value,
              range: [low, high]
            }
          )
        else
          response
        end

      Map.has_key?(dictionary_type, :type) ->
        # This is a subtype, so check super type
        super_type_key = String.to_atom(dictionary_type[:type])
        super_type = dictionary_types[super_type_key]

        if Map.has_key?(super_type, :range) do
          [low, high] = super_type[:range]

          if value < low or value > high do
            add_error(
              response,
              "attribute_value_exceeds_super_type_range",
              "Attribute \"#{attribute_path}\", type \"#{attribute_type_key}\"," <>
                " value is outside super type \"#{super_type_key}\" range of #{low} to #{high}.",
              %{
                attribute_path: attribute_path,
                attribute: attribute_name,
                super_type: super_type_key,
                type: attribute_type_key,
                value: value,
                super_type_range: [low, high]
              }
            )
          else
            response
          end
        else
          response
        end

      true ->
        response
    end
  end

  # Validate a string against a possible max_len constraint.
  # If attribute_type_key refers to a subtype, the subtype is checked first, and if the subtype
  # doesn't have a max_len, the supertype is checked.
  @spec validate_string_max_len(
          map(),
          String.t(),
          String.t(),
          String.t(),
          atom(),
          map()
        ) :: map()
  defp validate_string_max_len(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_type_key,
         dictionary_types
       ) do
    dictionary_type = dictionary_types[attribute_type_key]

    cond do
      Map.has_key?(dictionary_type, :max_len) ->
        # This is a primitive type or subtype with a range
        max_len = dictionary_type[:max_len]
        len = String.length(value)

        if len > max_len do
          add_error(
            response,
            "attribute_value_exceeds_max_len",
            "Attribute \"#{attribute_path}\" value length of #{len}" <>
              " exceeds type \"#{attribute_type_key}\" max length #{max_len}.",
            %{
              attribute_path: attribute_path,
              attribute: attribute_name,
              type: attribute_type_key,
              length: len,
              max_len: max_len,
              value: value
            }
          )
        else
          response
        end

      Map.has_key?(dictionary_type, :type) ->
        # This is a subtype, so check super type
        super_type_key = String.to_atom(dictionary_type[:type])
        super_type = dictionary_types[super_type_key]

        if Map.has_key?(super_type, :max_len) do
          max_len = super_type[:max_len]
          len = String.length(value)

          if len > max_len do
            add_error(
              response,
              "attribute_value_exceeds_super_type_max_len",
              "Attribute \"#{attribute_path}\", type \"#{attribute_type_key}\"," <>
                " value length #{len} exceeds super type \"#{super_type_key}\"" <>
                " max length #{max_len}.",
              %{
                attribute_path: attribute_path,
                attribute: attribute_name,
                super_type: super_type_key,
                type: attribute_type_key,
                length: len,
                max_len: max_len,
                value: value
              }
            )
          else
            response
          end
        else
          response
        end

      true ->
        response
    end
  end

  defp validate_string_regex(
         response,
         value,
         attribute_path,
         attribute_name,
         attribute_type_key,
         dictionary_types
       ) do
    dictionary_type = dictionary_types[attribute_type_key]

    cond do
      Map.has_key?(dictionary_type, :regex) ->
        # This is a primitive type or subtype with a range
        pattern = dictionary_type[:regex]

        case Regex.compile(pattern) do
          {:ok, regex} ->
            if Regex.match?(regex, value) do
              response
            else
              add_error(
                response,
                "attribute_value_regex_not_matched",
                "Attribute \"#{attribute_path}\" value" <>
                  " does not match regex of type \"#{attribute_type_key}\".",
                %{
                  attribute_path: attribute_path,
                  attribute: attribute_name,
                  type: attribute_type_key,
                  regex: regex,
                  value: value
                }
              )
            end

          {:error, {message, position}} ->
            Logger.warning(
              "SCHEMA BUG: Type \"#{attribute_type_key}\" specifies an invalid regex:" <>
                " \"#{message}\" at position #{position}, attribute path \"#{attribute_path}\""
            )

            add_error(
              response,
              "schema_bug_type_regex_invalid",
              "SCHEMA BUG: Type \"#{attribute_type_key}\" specifies an invalid regex:" <>
                " \"#{message}\" at position #{position}.",
              %{
                attribute_path: attribute_path,
                attribute: attribute_name,
                type: attribute_type_key,
                regex: pattern,
                regex_error_message: to_string(message),
                regex_error_position: position
              }
            )
        end

      Map.has_key?(dictionary_type, :type) ->
        # This is a subtype, so check super type
        super_type_key = String.to_atom(dictionary_type[:type])
        super_type = dictionary_types[super_type_key]

        if Map.has_key?(super_type, :regex) do
          pattern = dictionary_type[:regex]

          case Regex.compile(pattern) do
            {:ok, regex} ->
              if Regex.match?(regex, value) do
                response
              else
                add_error(
                  response,
                  "attribute_value_super_type_regex_not_matched",
                  "Attribute \"#{attribute_path}\", type \"#{attribute_type_key}\"," <>
                    " value does not match regex of super type \"#{super_type_key}\".",
                  %{
                    attribute_path: attribute_path,
                    attribute: attribute_name,
                    super_type: super_type_key,
                    type: attribute_type_key,
                    regex: pattern,
                    value: value
                  }
                )
              end

            {:error, {message, position}} ->
              Logger.warning(
                "SCHEMA BUG: Type \"#{super_type_key}\"" <>
                  " (super type of \"#{attribute_type_key}\") specifies an invalid regex:" <>
                  " \"#{message}\" at position #{position}, attribute path \"#{attribute_path}\""
              )

              add_error(
                response,
                "schema_bug_type_regex_invalid",
                "SCHEMA BUG: Type \"#{super_type_key}\"" <>
                  " (super type of \"#{attribute_type_key}\") specifies an invalid regex:" <>
                  " \"#{message}\" at position #{position}.",
                %{
                  attribute_path: attribute_path,
                  attribute: attribute_name,
                  type: super_type_key,
                  regex: pattern,
                  regex_error_message: to_string(message),
                  regex_error_position: position
                }
              )
          end
        else
          response
        end

      true ->
        response
    end
  end

  defp validate_attribute_deprecated(response, attribute_path, attribute_name, attribute_details) do
    if Map.has_key?(attribute_details, :"@deprecated") do
      add_warning_attribute_deprecated(
        response,
        attribute_path,
        attribute_name,
        attribute_details[:"@deprecated"]
      )
    else
      response
    end
  end

  @spec make_attribute_path(nil | String.t(), String.t()) :: String.t()
  defp make_attribute_path(parent_attribute_path, attribute_name) do
    if parent_attribute_path != nil and parent_attribute_path != "" do
      "#{parent_attribute_path}.#{attribute_name}"
    else
      attribute_name
    end
  end

  @spec make_attribute_path_array_element(String.t(), integer()) :: String.t()
  defp make_attribute_path_array_element(attribute_path, index) do
    "#{attribute_path}[#{index}]"
  end

  @spec new_response(map()) :: map()
  defp new_response(event) do
    metadata = event["metadata"]

    if is_map(metadata) do
      uid = metadata["uid"]

      if is_binary(uid) do
        %{uid: uid}
      else
        %{}
      end
    else
      %{}
    end
  end

  @spec add_error_required_attribute_missing(map(), String.t(), String.t()) :: map()
  defp add_error_required_attribute_missing(response, attribute_path, attribute_name) do
    add_error(
      response,
      "attribute_required_missing",
      "Required attribute \"#{attribute_path}\" is missing.",
      %{attribute_path: attribute_path, attribute: attribute_name}
    )
  end

  @spec add_warning_recommended_attribute_missing(map(), String.t(), String.t()) :: map()
  defp add_warning_recommended_attribute_missing(response, attribute_path, attribute_name) do
    add_warning(
      response,
      "attribute_recommended_missing",
      "Recommended attribute \"#{attribute_path}\" is missing.",
      %{attribute_path: attribute_path, attribute: attribute_name}
    )
  end

  @spec add_error_wrong_type(
          map(),
          String.t(),
          String.t(),
          any(),
          atom() | String.t(),
          String.t()
        ) :: map()
  defp add_error_wrong_type(
         response,
         attribute_path,
         attribute_name,
         value,
         expected_type,
         expected_type_extra \\ ""
       ) do
    {value_type, value_type_extra} = type_of(value)

    add_error(
      response,
      "attribute_wrong_type",
      "Attribute \"#{attribute_path}\" value has wrong type;" <>
        " expected #{expected_type}#{expected_type_extra}, got #{value_type}#{value_type_extra}.",
      %{
        attribute_path: attribute_path,
        attribute: attribute_name,
        value: value,
        value_type: value_type,
        expected_type: expected_type
      }
    )
  end

  @spec add_warning_class_deprecated(map(), map()) :: map()
  defp add_warning_class_deprecated(response, class) do
    deprecated = class[:"@deprecated"]

    add_warning(
      response,
      "class_deprecated",
      "Class #{class[:uid]} \"#{class[:name]}\" is deprecated. #{deprecated[:message]}",
      %{class_uid: class[:uid], class_name: class[:name], since: deprecated[:since]}
    )
  end

  @spec add_warning_attribute_deprecated(map(), String.t(), String.t(), map()) :: map()
  defp add_warning_attribute_deprecated(
         response,
         attribute_path,
         attribute_name,
         attribute_details
       ) do
    deprecated = attribute_details[:"@deprecated"]

    add_warning(
      response,
      "attribute_deprecated",
      "Dictionary attribute \"#{attribute_name}\" is deprecated. #{deprecated[:message]}",
      %{attribute_path: attribute_path, attribute: attribute_name, since: deprecated[:since]}
    )
  end

  @spec add_warning_object_deprecated(map(), String.t(), String.t(), map()) :: map()
  defp add_warning_object_deprecated(response, attribute_path, attribute_name, object) do
    deprecated = object[:"@deprecated"]

    add_warning(
      response,
      "object_deprecated",
      "Object \"#{object[:name]}\" is deprecated. #{deprecated[:message]}",
      %{
        attribute_path: attribute_path,
        attribute: attribute_name,
        object_name: object[:name],
        since: deprecated[:since]
      }
    )
  end

  @spec add_error(map(), String.t(), String.t(), map()) :: map()
  defp add_error(response, error_type, message, extra) do
    _add(response, :errors, :error, error_type, message, extra)
  end

  @spec add_warning(map(), String.t(), String.t(), map()) :: map()
  defp add_warning(response, warning_type, message, extra) do
    _add(response, :warnings, :warning, warning_type, message, extra)
  end

  @spec _add(map(), atom(), atom(), String.t(), String.t(), map()) :: map()
  defp _add(response, group_key, type_key, type, message, extra) do
    item = Map.merge(extra, %{type_key => type, message: message})
    Map.update(response, group_key, [item], fn items -> [item | items] end)
  end

  @spec finalize_response(map()) :: map()
  defp finalize_response(response) do
    # Reverse errors and warning so they are the order they were found,
    # which is (probably) more sensible than the reverse
    errors = lenient_reverse(response[:errors])
    warnings = lenient_reverse(response[:warnings])

    Map.merge(response, %{
      error_count: length(errors),
      warning_count: length(warnings),
      errors: errors,
      warnings: warnings
    })
  end

  defp lenient_reverse(nil), do: []
  defp lenient_reverse(list) when is_list(list), do: Enum.reverse(list)

  # Returns approximate OCSF type as a string for a value parsed from JSON. This is intended for
  # use when an attribute's type is incorrect. For integer values, this returns smallest type that
  # can be used for value.
  @spec type_of(any()) :: {String.t(), String.t()}
  defp type_of(v) do
    cond do
      is_float(v) ->
        # Elixir / Erlang floats are 64-bit IEEE floating point numbers, same as OCSF
        {"float_t", ""}

      is_integer(v) ->
        # Elixir / Erlang has arbitrary-precision integers, so we need to test the range
        cond do
          is_integer_t(v) ->
            {"integer_t", " (integer in range of -2^63 to 2^63 - 1)"}

          is_long_t(v) ->
            {"long_t", " (integer in range of -2^127 to 2^127 - 1)"}

          true ->
            {"big integer", " (outside of long_t range of -2^127 to 2^127 - 1)"}
        end

      is_boolean(v) ->
        {"boolean_t", ""}

      is_binary(v) ->
        {"string_t", ""}

      is_list(v) ->
        {"array", ""}

      is_map(v) ->
        {"object", ""}

      v == nil ->
        {"null", ""}

      true ->
        {"unknown type", ""}
    end
  end

  @min_int -Integer.pow(2, 63)
  @max_int Integer.pow(2, 63) - 1

  # Tests if value is an integer number in the OCSF integer_t range.
  defp is_integer_t(v) when is_integer(v), do: v >= @min_int && v <= @max_int
  defp is_integer_t(_), do: false

  @min_long -Integer.pow(2, 127)
  @max_long Integer.pow(2, 127) - 1

  # Tests if value is an integer number in the OCSF long_t range.
  defp is_long_t(v) when is_integer(v), do: v >= @min_long && v <= @max_long
  defp is_long_t(_), do: false
end
