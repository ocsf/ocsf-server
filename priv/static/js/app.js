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

function hide(name) {
  $(name).addClass('d-none');
}

function show(name) {
  $(name).removeClass('d-none');
}

function init_checkboxes() {
  init_base_event_checkbox('#btn-base-event', '.base-event');
  init_checkbox('#btn-reserved', '.reserved');
  init_checkbox('#btn-optional', '.optional');

  hide_attributes();
}

function init_checkbox(button, name) {
  if (window.localStorage.getItem(name) == null) {
    window.localStorage.setItem(name, name == '.reserved') 
  }

  const state = is_checked(name);
  $(button).prop("checked", state);

  $(button).on('click', function (e) {
    var classes;
    if (is_checked(".base-event")) {
      classes = name;
    }
    else {
      classes = ".event" + name;
    }

    if (e.target.checked) {
      window.localStorage.setItem(name, true);
      show(classes);
    } else {
      window.localStorage.setItem(name, false);
      hide(classes);
    }
  })
}

function init_base_event_checkbox(button, name) {
  if (window.localStorage.getItem(name) == null) {
    window.localStorage.setItem(name, true) 
  }

  const state = is_checked(name);
  $(button).prop("checked", state);

  $(button).on('click', function (e) {
    if (e.target.checked) {
      window.localStorage.setItem(name, true);

      show(".required");

      if (is_checked(".reserved")) {
        show(".reserved");
      }

      if (is_checked(".optional")) {
        show(".optional");
      }
    } else {
      window.localStorage.setItem(name, false);
      hide(name);
    }
  })
}

function hide_attributes() {
  if (!is_checked(".base-event")) {
    hide(".base-event");
  }

  if (!is_checked(".reserved")) {
    hide(".reserved");
  }

  if (!is_checked(".optional")) {
    hide(".optional");
  }
}

function is_checked(name) {
  return window.localStorage.getItem(name) === "true";
}

/* Table search function */
function searchInTable() {
  const input = document.getElementById("tableSearch");
  const filter = input.value.toUpperCase();
  const tbody = document.getElementsByClassName("searchable");

  for (t = 0; t < tbody.length; t++) {
    let tr = tbody[t].children;

    // Loop through all table rows, and hide those who don't match the search query
    for (i = 0; i < tr.length; i++) {
      const row = tr[i];
      const children = row.children;
      let hide = true;
      if (children.length > 2) {
        for (j = 0; hide && j < children.length - 1; j++) {
          const value = children[j].innerText;
          hide = value.toUpperCase().indexOf(filter) < 0;
        }
      }
      else {
        const value = children[0].innerText;
        hide = value.toUpperCase().indexOf(filter) < 0;
      }

      if (hide)
        row.style.display = "none";
      else
        row.style.display = "";
    }
  }
}
