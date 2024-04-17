module.exports = (() => {
  try {
    return require('./bin/tim-' + process.platform + '.node');
  } catch (e) {
    // 
  }
})();