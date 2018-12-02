function FreeBusy(start, freebusy, interval) {
    this.freebusy = freebusy;
    this.start    = moment(start);
    this.interval = interval;
    this.end = moment(this.start).add(this.freebusy.length * this.interval, 'minutes')

    return this;
};

FreeBusy.prototype.slot = function (time) {
    var d = moment(time).diff(this.start, 'minutes');
    return Math.floor(d / this.interval);
};

FreeBusy.prototype.slice = function (from, to) {
    var s = this.slot(from);
    var e = this.slot(to);

    return this.freebusy.substring(s, e);
};

FreeBusy.prototype.time = function(slot){
    return moment(this.start).add(slot * this.interval, 'minutes').format()
}

FreeBusy.prototype.asSlots = function(){
    var p = '';
    var a = [];
    var k = 0;

    this.freebusy
    	.replace(/[123456789]/g, '1')
	.split('')
	.forEach(e => {
	    if (e != p) {
		k = a.length ? a[a.length-1][2] + a[a.length-1][1] : 0;
		a.push([ e, k, 1 ])
	    } else {
		a[a.length-1][2]++
	    }
	    p = e;
	})
    
    a = a.map(e => {
	return { start: this.time(e[1]), end: this.time(e[1] + e[2]), free: e[0].match(/0/) ? true : false }
    })
    
    return a;
}

FreeBusy.prototype.similar = function(f){
    return this.freebusy.length == f.freebusy.length && this.start.format() == f.start.format();
}

FreeBusy.prototype.overlap = function(...a) {
    var tentative = typeof a[a.length - 1] == 'boolean' ? a.pop() : false;
    var t = this;

    while (a.length) {
	if (!t.similar(a[0])) { console.log('freebusy strings are of different length or have different start'); return; }

	var o = a.shift().freebusy.split('');
	var f = t.freebusy.split('');
	var x = [];

	for (var i = 0; i < (f.length); i++) { x.push(f[i] > o[i] ? f[i] : o[i] ) }
	
	t = new FreeBusy(this.start, x.join(''))
    }
    
    return t;
}

FreeBusy.prototype.fold = function(length) {
    var str = this.freebusy;

    var r = [];
    for (p = 0; p < str.length; p += length) { r.push(str.substr(p, length)) }

    return r;
}

FreeBusy.prototype.clone = function(){
    var fb = new FreeBusy(this.start, this.freebusy, this.interval)
    return fb;
}

FreeBusy.prototype.combine = function() {
    var args = Array.isArray(arguments[0]) ?
	arguments[0] : [].slice.call(arguments);

    args.push(this);
    this.freebusy = FreeBusy.combine(args).freebusy;
}

FreeBusy.combine = function(){
    var args = Array.isArray(arguments[0]) ?
	arguments[0] : [].slice.call(arguments);

    var fb = args
	.map(e => { return e.freebusy })
	.map(e => {  return e.split('') })
	.reduce(function(acc, f){
	    acc = f.map(function(e, i){
		return e | acc[i]
	    })
	    return acc;
	}, []).join('');
    
    return new FreeBusy(args[0].start, fb, args[0].interval)
}

FreeBusy.prototype.loadFactor = function(a){
    if (a) {
	var h = a.freebusy.split('');
	return this.freebusy.split('')
	    .filter(e => {
		var b = h.shift() || 0;
		return (e == 0 && b == 0)
	    })
	    .length
    } else {
	return this.freebusy.split('')
	    .filter(e => { return e == 0 })
	    .length
    }
}
