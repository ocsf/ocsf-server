// Copyright 2021 Splunk Inc.
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//   http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
export default function define(runtime, observer) {
  let width = getWidth() * 0.75;
  let height = getHeight() * 0.65;

  const main = runtime.module();
  const params = extensions_params();
  const fileAttachments = new Map([["schema.json", new URL("/api/schema" + params, import.meta.url)]]);

  main.builtin("FileAttachment", runtime.fileAttachments(name => fileAttachments.get(name)));

  main.variable("viewof tile").define("viewof tile", ["d3", "html"], function (d3, html) {
    const options = [];

    const form = html`<form style="display: flex; align-items: center; min-height: 50px;"><select name=i>${options.map(o => Object.assign(html`<option>`, { textContent: o.name, selected: o.selected }))}`;
    form.i.onchange = () => form.dispatchEvent(new CustomEvent("input"));
    form.oninput = () => form.value = d3.treemapBinary;
    form.oninput();

    return form;
  });

  main.variable("tile").define("tile", ["Generators", "viewof tile"], (G, _) => G.input(_));

  main.variable(observer("chart")).define("chart", ["treemap", "data", "d3"],
    function (treemap, data, d3) {
      const root = treemap(data);

      const svg = d3.create("svg")
        .attr("viewBox", [-6, 30, width, height])
        .style("font", "12px open-sans")
        .attr("class", "schema");

      const leaf = svg.selectAll("g")
        .data(root.leaves())
        .join("g")
        .attr("transform", d => `translate(${d.x0},${d.y0})`);

      // Add boxes for the classes
      leaf
        .append("rect")
        .style("stroke", "#b0b0b0")
        .attr("fill", "#f8f8f8")
        .attr("width", d => d.x1 - d.x0)
        .attr("height", d => d.y1 - d.y0);

      // Add title for the classes
      leaf
        .append("a")
        .attr("xlink:href", function (d) { return "/classes/" + make_path(d.data.extension, d.data.type) + params; })
        .append("text")
        .on('mouseover', function (d, i) {
            d3.select(this)
              .attr('opacity', .75);})
        .on('mouseout', function (d, i) {
            d3.select(this)
              .attr('opacity', 1)})
        .selectAll("tspan")
        .data(d => d.data.name.split(/(?=[A-Z][a-z])|\s+/g).concat(d.data.uid))
        .join("tspan")
        .attr("x", 3)
        .attr("y", (d, i) => `${1 + i * 0.95}em`)
        .text(d => d)
        .style("fill", "#545aa7");

      // Add title for the categories
      svg
        .selectAll("categories")
        .data(root.descendants().filter(function (d) { return d.depth == 1 }))
        .enter()
        .append("a")
        .attr("xlink:href", function (d) { return "/categories/" + d.data.type + params; })
        .append("text")
        .attr("x", function (d) { return d.x0 + 5 })
        .attr("y", function (d) { return d.y0 + 18 })
        .text(function (d) { return "[" + d.data.uid + "] " + d.data.name })
        .style("fill", "#545af0")    
        .style("font", "16px open-sans")
        .on('mouseover', function (d, i) {
            d3.select(this)
              .attr('opacity', .75);})
        .on('mouseout', function (d, i) {
            d3.select(this)
              .attr('opacity', 1)});

      return svg.node();
    }
  );

  main.variable("data").define("data", ["FileAttachment"], function (FileAttachment) {
    return (FileAttachment("schema.json").json())
  });

  main.variable("treemap").define("treemap", ["d3", "tile"], function (d3, tile) {
    return (
      data => d3.treemap()
        .tile(tile)
        .size([width, height])
        .paddingTop(28)
        .paddingRight(6)
        .paddingInner(3) // Padding between each rectangle
        (d3.hierarchy(data).sum(d => d.value)))
  });

  main.variable("format").define("format", ["d3"], function (d3) { return (d3.format(",d")) });
  main.variable("d3").define("d3", ["require"], function (require) { return (require("d3@6")) });

  return main;
}

function make_path(extension, type) {
  if (extension == null) {
    return type;
  }

  return extension + "/" + type;
}

function getWidth() {
  return Math.max(
    document.body.scrollWidth,
    document.documentElement.scrollWidth,
    document.body.offsetWidth,
    document.documentElement.offsetWidth,
    document.documentElement.clientWidth
  );
}

function getHeight() {
  return Math.max(
    document.body.scrollHeight,
    document.documentElement.scrollHeight,
    document.body.offsetHeight,
    document.documentElement.offsetHeight,
    document.documentElement.clientHeight
  );
}
