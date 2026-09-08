function notchBounds(area, position, accountCount, expanded, settings, details = false) {
  const side = position === 'left' || position === 'right';
  const railHeight = 48 + accountCount * 54;
  const overviewWidth = Math.max(110, Math.min(420, 48 + accountCount * 66));
  const open = expanded || settings;
  const width = Math.min(area.width, settings ? (side ? 490 : 440) : details && open ? (side ? 410 : Math.max(340, overviewWidth)) : open ? (side ? 60 : overviewWidth) : side ? 6 : 80);
  const height = Math.min(area.height, settings ? 580 : details && open ? Math.min(580, side ? Math.max(240, railHeight) : 260) : open ? (side ? Math.min(580, railHeight) : 44) : side ? 80 : 6);
  const x = position === 'left' ? area.x : position === 'right' ? area.x + area.width - width : area.x + Math.round((area.width - width) / 2);
  const y = position === 'bottom' ? area.y + area.height - height : side ? area.y + Math.round((area.height - height) / 2) : area.y;
  return { x, y, width, height };
}
module.exports = { notchBounds };
