// extensions.js
let extensions = new Map();

function init_extensions() {
  read_extensions();
  
  $('#select_all').on('click',function(){
    if(this.checked){
      $('.extension_checkbox').each(function(){
        this.checked = true;
        extensions.set(this.id, true);        
      });
    } else {
      $('.extension_checkbox').each(function(){
        this.checked = false;
        extensions.set(this.id, false);
      });
    }
    save_extensions();    
  });
  
  $('.extension_checkbox').on('click',function(){
    extensions.set(this.id, this.checked);
    check_select_all();
    save_extensions();    
  });
}

function read_extensions() {
  const data = window.localStorage.getItem("selected-extensions");

  if (data == null) {
    $('.extension_checkbox').each(function() {
      extensions.set(this.id, this.checked);
    });
    
    save_extensions();
  } else {
    extensions = new Map(JSON.parse(data));
    extensions.forEach((checked, extension) => {
      if (extension.length > 0) {
        $('#' + extension).prop('checked', checked);
      }
    });
    check_select_all();
  }
}

function check_select_all() {
  if($('.extension_checkbox:checked').length == $('.extension_checkbox').length){
    $('#select_all').prop('checked',true);
  }else{
    $('#select_all').prop('checked',false);
  }
}

function save_extensions() {
  const data = JSON.stringify(Array.from(extensions.entries()));
  window.localStorage.setItem("selected-extensions", data);

  const params = selected_extensions(extensions);
  $(".extensions a").each(function() {
    this.href = parse_url(this.href) + params;
  });
}

function parse_url( url ) {
  return url.split("?")[0];
}
