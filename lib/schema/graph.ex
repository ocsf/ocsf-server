# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Graph do
  @moduledoc """
  This module generates graph data to display event class diagram.
  """

  @doc """
  Builds graph data for the given class.
  """
  @spec build(map()) :: map()
  def build(class) do
    %{
      nodes: build_nodes(class),
      edges: build_edges(class),
      class: Map.delete(class, :attributes) |> Map.delete(:objects)
    }
  end

  defp build_nodes(class) do
    node =
      Map.new()
      |> Map.put(:color, "#F5F5C8")
      |> Map.put(:id, class.name)
      |> Map.put(:label, class.caption)

    build_nodes([node], class)
  end

  defp build_nodes(nodes, class) do
    Map.get(class, :objects)
    |> Enum.reduce(nodes, fn {_name, obj}, acc ->
      node = %{
        id: obj.name,
        label: obj.caption
      }

      [node | acc]
    end)
  end

  defp build_edges(class) do
    objects = Map.new(class.objects)
    build_edges([], class, objects)
  end

  defp build_edges(edges, class, objects) do
    Map.get(class, :attributes)
    |> Enum.reduce(edges, fn {name, obj}, acc ->
      case obj.type do
        "object_t" ->
          edge = %{
            from: class.name,
            to: obj.object_type,
            label: Atom.to_string(name)
          }

          acc = [edge | acc]

          if class.name != obj.object_type do
            o = objects[String.to_atom(obj.object_type)]
            build_edges(acc, o, objects)
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end
end
