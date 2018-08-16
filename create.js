use aroundthetable-dev
db.activities.createIndex({"location.coordinates": "2dsphere"})
