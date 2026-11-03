fetch(url)
  .then(r => r.json())
  .then(d => {
    console.log(d)
  })
  .catch(e => console.error(e))
