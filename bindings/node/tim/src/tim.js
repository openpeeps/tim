module.exports = (() => {
  if(process.platform === 'darwin') {
    return require('./bin/tim-macos.node');
  } else if(process.platform === 'linux') {
    return require('./bin/tim-linux.node');
  } else {
    throw new Error('Tim Engine - Unsupported platform ' + process.platform)
  }
})();