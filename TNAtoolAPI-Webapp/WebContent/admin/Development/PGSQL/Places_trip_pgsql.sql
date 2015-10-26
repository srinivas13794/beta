﻿drop table if exists census_places_trip_map;

CREATE TABLE census_places_trip_map
(
  gid serial NOT NULL,
  agencyid character varying(255),
  agencyid_def character varying(255),
  routeid character varying(255),
  placeid character varying(7),
  tripid character varying(255),
  serviceid character varying(255),
  stopscount integer,  
  length float,
  tlength int,
  shape geometry(multilinestring),
  uid varchar(512),
  CONSTRAINT census_places_trip_map_pkey PRIMARY KEY (gid),
  CONSTRAINT census_places_trip_map_fkey FOREIGN KEY (agencyid, tripid)
      REFERENCES gtfs_trips (agencyid, id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION
)
WITH (
  OIDS=FALSE
);
ALTER TABLE census_places_trip_map
  OWNER TO postgres;

with groutes as(SELECT routeid, ST_multi(ST_Collect(ST_SetSRID(ST_MakePoint(stops.lon, stops.lat), 4326))) multi
		FROM gtfs_stop_route_map AS map INNER JOIN gtfs_stops AS stops
		ON map.agencyid = stops.agencyid
		AND map.stopid = stops.id
		GROUP BY routeid
)
insert into census_places_trip_map(tripid, agencyid, agencyid_def, serviceid, routeid,  placeid, shape, length, uid) 
select trip.id, trip.agencyid, trip.serviceid_agencyid, trip.serviceid_id, trip.route_id, place.placeid, st_multi(ST_CollectionExtract(st_union(ST_Intersection(trip.shape,place.shape)),2)), (ST_Length(st_transform(ST_Intersection(trip.shape,place.shape),2993))/1609.34), trip.uid
from gtfs_trips trip
inner join groutes on trip.route_id=groutes.routeid
inner join census_places place on  st_intersects(place.shape,trip.shape)=true and st_intersects(place.shape,multi)=true group by trip.id, trip.agencyid, place.placeid;

update census_places_trip_map set stopscount = res.cnt+0 from 
(select count(stop.id) as cnt, stop.placeid as cid, stime.trip_agencyid as aid, stime.trip_id as tid 
from gtfs_stops stop inner join gtfs_stop_times stime 
on stime.stop_agencyid = stop.agencyid and stime.stop_id = stop.id group by stime.trip_agencyid, stime.trip_id, stop.placeid) as res
where placeid =  res.cid and agencyid = res.aid and tripid=res.tid;

update census_places_trip_map set stopscount=0 where stopscount IS NULL;

update census_places_trip_map map set tlength=res.ttime from (
select max(stimes.departuretime)-min(stimes.arrivaltime) as ttime, 
stimes.agencyid, stimes.tripid, stimes.geoid from (
select stime.arrivaltime, stime.departuretime, stime.trip_agencyid as agencyid, stime.trip_id as tripid, stop.placeid as geoid
from gtfs_stop_times stime inner join gtfs_stops stop on stime.stop_agencyid = stop.agencyid and stime.stop_id = stop.id) as stimes
where stimes.arrivaltime>0 and stimes.departuretime>0 group by stimes.agencyid, stimes.tripid, stimes.geoid) as res 
where res.agencyid = map.agencyid and res.tripid=map.tripid and res.geoid=map.placeid;

update census_places_trip_map set tlength=0 where tlength isnull;