function notchBounds(area, position, accountCount, expanded, settings, details = false) {
  const side = position === 'left' || position === 'right';
  // Rail: 2×68 end padding (clears the ear and corner taper) + gear (28) + one 24px gap, then the rings.
  const railHeight = 188 + accountCount * 67 + Math.max(0, accountCount - 1) * 31;
  // Row: 2×50 end padding + spacer and gear (2×28) + two 24px gaps, then the rings.
  const overviewWidth = Math.max(204, Math.min(640, 204 + accountCount * 44 + Math.max(0, accountCount - 1) * 31));
  const open = expanded || settings;
  const width = Math.min(area.width, settings ? (side ? 490 : 500) : details && open ? (side ? 420 : Math.max(420, overviewWidth)) : open ? (side ? 70 : overviewWidth) : side ? 10 : 80);
  const height = Math.min(area.height, settings ? 620 : details && open ? Math.min(580, side ? Math.max(340, railHeight) : 340) : open ? (side ? Math.min(580, railHeight) : 94) : side ? 80 : 10);
  const x = position === 'left' ? area.x : position === 'right' ? area.x + area.width - width : area.x + Math.round((area.width - width) / 2);
  const y = position === 'bottom' ? area.y + area.height - height : side ? area.y + Math.round((area.height - height) / 2) : area.y;
  return { x, y, width, height };
}
module.exports = { notchBounds };
