// for phoenix_html support, including form and button helpers
// copy the following scripts into your javascript bundle:
// * https://raw.githubusercontent.com/phoenixframework/phoenix_html/v2.10.0/priv/static/phoenix_html.js

function init_checkboxes() {
  init_checkbox('#btn-reserved', '.reserved');
  init_checkbox('#btn-extensions', '.extension');
  init_checkbox('#btn-base-event', '.base-event');
}

function init_checkbox(button, name) {
  const state = window.localStorage.getItem(name) === "true";
  $(button).prop("checked", state);
  if (state) {
    $(name).removeClass('d-none');
  } else {
    // hide
    $(name).addClass('d-none');
  }

  $(button).on('click', function (e) {
    if (e.target.checked) {
      window.localStorage.setItem(name, true);
      $(name).removeClass('d-none');
    } else {
      // hide
      window.localStorage.setItem(name, false);
      $(name).addClass('d-none');
    }
  })

}