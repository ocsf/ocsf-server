// extensions.js
const extensionsKey = "selected-extensions";
let extensions = new Map();

function init_extensions() {
  read_extensions();
  
  $('#select_all').on('click',function(){
    if(this.checked){
      $('.checkbox').each(function(){
        this.checked = true;
        extensions.set(this.id, true);        
      });
    } else {
      $('.checkbox').each(function(){
        this.checked = false;
        extensions.set(this.id, false);
      });
    }
    save_extensions();    
  });
  
  $('.checkbox').on('click',function(){
    extensions.set(this.id, this.checked);
    check_select_all();
    save_extensions();    
  });
}

function save_extensions() {
  const data = JSON.stringify(Array.from(extensions.entries()));
  window.localStorage.setItem(extensionsKey, data);
}

function read_extensions() {
  const data = window.localStorage.getItem(extensionsKey);

  if (data == null) {
    $('.checkbox').each(function() {
      extensions.set(this.id, this.checked);
    });
    
    save_extensions();
  } else {
    extensions = new Map(JSON.parse(data));
    extensions.forEach((checked, extension) => 
      $('#' + extension).prop('checked',checked));

    check_select_all();
  }
}

function check_select_all() {
  if($('.checkbox:checked').length == $('.checkbox').length){
    $('#select_all').prop('checked',true);
  }else{
    $('#select_all').prop('checked',false);
  }
}

function get_selected_extensions() {
  const selected = [];
  extensions.forEach(function(checked, extension) {
    if (checked) selected.push(extension);
  });

  return selected;
}
