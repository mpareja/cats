module.exports = require('rc')('cats', {
  dataDir: 'data',
  log: {
    level: 'info'
  },
  stats: {
    disable: true
  },
  port: 8090
});
