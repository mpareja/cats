var beatrix = require('beatrix');
var request = require('request');
var config = require('./config.js');

var gm = require('gm');

var app = beatrix.bootstrapService('cats', config.port, config);
app.server.get('/:phrase', function (req, res, next) {
  var cats = request('http://thecatapi.com/api/images/get.php');
  gm(cats)
    .pointSize(50)
    .drawText(30, 40, req.params.phrase)
    .stream()
    .pipe(res)
      .on('finish', next);
});
