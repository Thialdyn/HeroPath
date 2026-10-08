/* WoWForeverMap outdoor Azeroth projection.
   Projection constants are kept local so the renderer has no external runtime dependency.
   Scope intentionally limited to exterior Azeroth: Eastern Kingdoms (mapID 0)
   and Kalimdor (mapID 1). */
(function (root) {
  "use strict";
  var TILE_SIZE = 512;
  var GRID_SIZE = 128;
  var GRID_YARDS = 1600 / 3;
  var G = TILE_SIZE / GRID_SIZE;
  var MAX_ZOOM = 7;
  var MAX_PIXEL_SCALE = 128; // 512px tile / 4 map units at z7.
  var CONTINENTS = {
    0: { id: 0, realm: "azeroth", name: "Eastern Kingdoms", offset: { x: 26, y: -18 } },
    1: { id: 1, realm: "azeroth", name: "Kalimdor", offset: { x: -19, y: -9 } }
  };

  function continent(mapID) { return CONTINENTS[Number(mapID)] || null; }
  function worldToMap(mapID, worldX, worldY) {
    var c = continent(mapID);
    worldX = Number(worldX); worldY = Number(worldY);
    if (!c || !isFinite(worldX) || !isFinite(worldY)) return null;
    var first = 32 - worldY / GRID_YARDS + c.offset.x;
    var second = 32 - worldX / GRID_YARDS + c.offset.y;
    return { lat: -second * G, lng: first * G, continent: c };
  }
  function mapToWorld(mapID, lat, lng) {
    var c = continent(mapID);
    lat = Number(lat); lng = Number(lng);
    if (!c || !isFinite(lat) || !isFinite(lng)) return null;
    return {
      mapID: Number(mapID),
      x: (32 - (-lat / G - c.offset.y)) * GRID_YARDS,
      y: (32 - (lng / G - c.offset.x)) * GRID_YARDS
    };
  }
  function worldToMaxPixel(mapID, worldX, worldY) {
    var p = worldToMap(mapID, worldX, worldY);
    return p ? { x: p.lng * MAX_PIXEL_SCALE, y: -p.lat * MAX_PIXEL_SCALE } : null;
  }
  function maxPixelToWorld(mapID, px, py) {
    return mapToWorld(mapID, -Number(py) / MAX_PIXEL_SCALE, Number(px) / MAX_PIXEL_SCALE);
  }
  function isOutdoorAzerothMap(mapID) { return !!continent(mapID); }

  var api = {
    TILE_SIZE: TILE_SIZE, GRID_SIZE: GRID_SIZE, GRID_YARDS: GRID_YARDS,
    MAX_ZOOM: MAX_ZOOM, MAX_PIXEL_SCALE: MAX_PIXEL_SCALE,
    CONTINENTS: CONTINENTS,
    continent: continent,
    isOutdoorAzerothMap: isOutdoorAzerothMap,
    worldToMap: worldToMap,
    mapToWorld: mapToWorld,
    worldToMaxPixel: worldToMaxPixel,
    maxPixelToWorld: maxPixelToWorld
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.OutdoorAzerothProjection = api;
})(typeof window !== "undefined" ? window : globalThis);
