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
          hide =  value.toUpperCase().indexOf(filter) < 0;
        }
      }
      else {
        const value = children[0].innerText;
        hide =  value.toUpperCase().indexOf(filter) < 0;
      }

      if (hide)
        row.style.display = "none";
      else
        row.style.display = "";
    }
  }
}
