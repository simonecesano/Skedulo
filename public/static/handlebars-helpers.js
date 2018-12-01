Handlebars.registerHelper('eq', function(a, b, opts) {
    if(a === b) { 
        return opts.fn(this);
    } else {
        return opts.inverse(this);
    }
});
Handlebars.registerHelper('match', function(a, b, opts) {
    var r = new RegExp(b, "i");
    if(a.match(r)) { 
        return opts.fn(this);
    } else {
        return opts.inverse(this);
    }
});
Handlebars.registerHelper('moment-format', function() {
    var date = arguments[0], format = arguments[1], timezone = arguments[2];
    date = moment(date)
    
    if (typeof timezone == 'string') {
	return date.tz(timezone).format(format);
    } else {
	return date.format(format);
    }
});
Handlebars.registerHelper('md5', function(string) {
    return md5(string);
});
