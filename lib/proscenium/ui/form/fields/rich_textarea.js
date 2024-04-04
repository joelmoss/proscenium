import "trix"

document.addEventListener("trix-file-accept", function (event) {
  // Prevent attachment drag and drop
  event.preventDefault()
})
