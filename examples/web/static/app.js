// examples/web - served from disk by the static route, byte for byte
document.addEventListener("DOMContentLoaded", function () {
  var items = document.querySelectorAll("ul li");
  if (items.length > 0) {
    document.title = document.title + " (" + items.length + ")";
  }
});
