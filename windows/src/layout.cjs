function notchBounds(area, position, accountCount, expanded, settings, details = false) {
  const side = position === 'left' || position === 'right';
  const railHeight = 163 + accountCount * 67 + Math.max(0, accountCount - 1) * 31;
  const overviewWidth = Math.max(163, Math.min(600, 163 + accountCount * 44 + Math.max(0, accountCount - 1) * 31));
  const open = expanded || settings;
  const width = Math.min(area.width, settings ? (side ? 490 : 480) : details && open ? (side ? 420 : Math.max(380, overviewWidth)) : open ? (side ? 70 : overviewWidth) : side ? 10 : 80);
  const height = Math.min(area.height, settings ? 620 : details && open ? Math.min(580, side ? Math.max(280, railHeight) : 330) : open ? (side ? Math.min(580, railHeight) : 94) : side ? 80 : 10);
  const x = position === 'left' ? area.x : position === 'right' ? area.x + area.width - width : area.x + Math.round((area.width - width) / 2);
  const y = position === 'bottom' ? area.y + area.height - height : side ? area.y + Math.round((area.height - height) / 2) : area.y;
  return { x, y, width, height };
}
module.exports = { notchBounds };
