later.date.localTime();

moment.prototype.getTime = moment.prototype.valueOf;

var WorkDay = function(starts, ends, invert){
    this.starts = starts;
    this.ends   = ends;
    this.invert = invert;
    return this;
}

WorkDay.prototype.schedule = function(start, end){
    var a = later.schedule(this.starts).next(Infinity, start, end);
    var b = later.schedule(this.ends).next(Infinity, start, end);
    
    if (a[0] > b[0]) { a.unshift(start) }

    var t = _.zip(a, b).map(e => { return { start: e[0], end: e[1], free: true } });

    var f = []

    t.reduce(function(a, e, i){
	if (i < t.length - 1) {
	    a.push(e, { start: e.end, end: t[i+1].start, free: false });
	} else {
	    a.push(e);
	}
	return a;
    }, f)

    if (f[0].start > start) {
	f.unshift({ start: start, end: f[0].start, free: (!f[0].free) });
    }

    if (f[f.length-1].end < end) {
	f.push({ start: f[f.length-1].end, end: end, free: (!f[f.length-1].free) });
    }
    f.forEach(e => {
	e.start = moment(e.start);
	e.end = moment(e.end);	
	e.free = this.invert ? !e.free : e.free
    })
    return f;
}

WorkDay.prototype.freebusy = function(start, end, duration){
    var t = this.schedule(start, end);
    var a = t.map(e => {
	var n = { free: e.free };
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

    var duration = args.pop();
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

