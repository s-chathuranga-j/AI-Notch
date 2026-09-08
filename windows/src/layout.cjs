function notchBounds(area, position, accountCount, expanded, settings) {
  const side = position === 'left' || position === 'right';
  const railHeight = 48 + accountCount * 54;
  const width = Math.min(area.width, settings ? (side ? 490 : 440) : expanded ? (side ? 410 : 360) : side ? 60 : Math.max(248, Math.min(420, 132 + accountCount * 66)));
  const height = Math.min(area.height, settings ? 580 : expanded ? Math.min(580, Math.max(96 + accountCount * 145, side ? railHeight : 0)) : side ? Math.min(580, railHeight) : 44);
  const x = position === 'left' ? area.x : position === 'right' ? area.x + area.width - width : area.x + Math.round((area.width - width) / 2);
  const y = position === 'bottom' ? area.y + area.height - height : side ? area.y + Math.round((area.height - height) / 2) : area.y;
  return { x, y, width, height };
}
module.exports = { notchBounds };
