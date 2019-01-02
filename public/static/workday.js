later.date.UTC();

moment.prototype.getTime = moment.prototype.valueOf;

var WorkDay = function(schedule){

    var days = schedule.days.map(function(e) {
	return parseInt(moment().day(e).format('d')) + 1;
    });

    this.starts = later.parse.recur()
	.on(schedule.start).time()
	.on(days).dayOfWeek()

    this.ends = later.parse.recur()
	.on(schedule.end).time()
	.on(days).dayOfWeek()

    this.tz = schedule.tz || Intl.DateTimeFormat().resolvedOptions().timeZone;

    this.invert = schedule.invert;

    return this;
}

WorkDay.parse = function(starts, ends, invert, tz){
    var wd = new WorkDay({ start: '8:00', end: '18:00', days: ['Mon', 'Tue'] })
    
    wd.starts = later.parse.text(starts),
    wd.ends   = later.parse.text(ends),
    wd.invert = invert;
    wd.tz = tz || Intl.DateTimeFormat().resolvedOptions().timeZone;

    return wd;
}

WorkDay.prototype.schedule = function(start, end, destTZ){
    // if the start and end tz is different from the workday's
    // fix start and end

    destTZ = destTZ || Intl.DateTimeFormat().resolvedOptions().timeZone;

    startF = moment(start).tz(this.tz);
    endF   = moment(end).tz(this.tz);    
    
    var a = later.schedule(this.starts).next(Infinity, startF, endF);
    var b = later.schedule(this.ends).next(Infinity, startF, endF);
    
    if (a[0] > b[0]) { a.unshift(start) }

    var t = _.zip(a, b) // combine the two schedules
	.map(e => { return { start: e[0], end: e[1], free: true } });
    
    var f = []

    t.reduce(function(a, e, i){
	if (i < t.length - 1) {
	    a.push(e, { start: e.end, end: t[i+1].start, free: false });
	} else {
	    a.push(e);
	}
	return a;
    }, f)

    f.forEach(e => {
	e.start = WorkDay.mapTZ(e.start, this.tz, destTZ),
	e.end =   WorkDay.mapTZ(e.end,   this.tz, destTZ),
	e.free =  this.invert ? !e.free : e.free
    })

    if (f[0].start > start) {
	f.unshift({ start: start, end: f[0].start, free: (!f[0].free) });
    }

    if (f[f.length-1].end < end) {
	f.push({ start: f[f.length-1].end, end: end, free: (!f[f.length-1].free) });
    }


    return f;
}

WorkDay.prototype.freebusy = function(start, end, duration, destTZ){

    duration = duration || WorkDay.duration || 60;
    start    = start    || WorkDay.start    || new Date((new Date()).setHours(0, 0, 0, 0));
    end      = end      || WorkDay.end      || new Date((new Date()).setHours(0, 0, 0, 0) + (7 * 24 * 3600 * 1000));
    destTz   = destTZ   || WorkDay.destTZ   || Intl.DateTimeFormat().resolvedOptions().timeZone;
    
    var t = this.schedule(start, end, destTZ);
    console.log(t);
    var a = t.map(e => {
	var n = { free: e.free };
	// check that everything is moment()

	e.start = moment.isMoment(e.start) ? e.start : moment(e.start);
	e.end   = moment.isMoment(e.end)   ? e.end   : moment(e.end);
	
	if (e.free) {
	    n.start = e.start.clone().minute(Math.ceil(e.start.minute() / duration) * duration);
	    n.end   = e.end.clone().minute(Math.floor(e.end.minute() / duration) * duration);
	} else {
	    n.start = e.start.clone().minute(Math.floor(e.start.minute() / duration) * duration);
	    n.end   = e.end.clone().minute(Math.ceil(e.end.minute() / duration) * duration);
	}
	
	n.duration = n.end.diff(n.start, 'minutes');
	n.slot_count = n.duration / duration;
	n.string = (n.free ? '0' : '1').repeat(n.slot_count); 
	return n;
    })
    return a.map(e => { return e.string }).join('')   
}

WorkDay.prototype.freebusyObj = function(start, end, duration, destTZ){
    start    = start    || WorkDay.start    || new Date((new Date()).setHours(0, 0, 0, 0));
    duration = duration || WorkDay.duration || 60;
    
    return new FreeBusy(start, this.freebusy(start, end, duration, destTZ), duration)
};



WorkDay.wcombine = function() {
    var args = [].slice.call(arguments)

    var duration = args.pop();
    var end   = args.pop();
    var start = args.pop();    

    var wd = args.map(e => { return e.freebusy(start, end, duration ) })

    var a =  wd.shift().split('');

    while (wd.length) {
	var b = wd.shift().split('');
	a = a.map(function(e, i){
	    return e | b[i]
	})
    }
    return a.join('');
}

WorkDay.combine = function() {
    var args = [].slice.call(arguments)

    var duration = args.length == 5 ? args.pop() : 60;

    var end   = args.pop();
    var start = args.pop();    

    var acc = []; 

    var r = args
	.map(e => { return e.freebusy(start, end, duration ) })
	.map(e => { return e.split('') })
	.reduce(function(acc, f){
	    acc = f.map(function(e, i){
		return e | acc[i]
	    })
	    return acc;
    })
    return r.join('');
}

WorkDay.mapTZ = function(date, sourceTZ, destTZ) {
    var noTZ   = moment(date).tz('UTC').format('YYYY-MM-DDTHH:mm:ss');
    var fromTZ = moment.tz(noTZ, sourceTZ)
    var toTZ   = moment.tz(fromTZ, destTZ);

    return toTZ
}
