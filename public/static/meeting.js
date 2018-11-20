var _fix = function(o) {
    Object.keys(o).forEach(function(k, i) {
	if(typeof o[k] === "object"){
	    _fix(o[k]);
	} else {
	    if (typeof o[k] === "string" && o[k].match(/\d{4}-[01]\d-[0-3]\dT[0-2]\d:[0-5]\d:[0-5]\d([+-][0-2]\d:[0-5]\d|Z)/i)) {
		var d = new Date(o[k]);
		o[k] = d;
	    } else if (typeof o[k] === "string" && o[k].match(/^false$|^true$/)) {
		o[k] = eval(o[k]);
	    };
	}
    }); 
}

var Meeting = function(d) {
    // this = Object.assign(d, object1);;

    _fix(d)

    d.duration = function(){
	return this.End - this.Start
    }

    d.IsMine = d.MyResponseType.match(/Organizer/i) ? true : false;
    d.Start = new Date(d.Start);
    d.End = new Date(d.End);    
    
    if (d.ConflictingMeetings) {
	if (!Array.isArray(d.ConflictingMeetings.CalendarItem)) { d.ConflictingMeetings.CalendarItem = [ d.ConflictingMeetings.CalendarItem ]}
    } else {
	d.ConflictingMeetings = { CalendarItem: [] }
    }

    if (d.RequiredAttendees) {
	if (!Array.isArray(d.RequiredAttendees.Attendee)) { d.RequiredAttendees.Attendee = [ d.RequiredAttendees.Attendee ]}
    } else {
	d.RequiredAttendees = { Attendee: [] }
    }

    d.RequiredAttendeesList = d.RequiredAttendees.Attendee.length > 10 ?
	`${d.RequiredAttendees.Attendee.length} attendees` : d.RequiredAttendees.Attendee.map(function(e){
	    return e.Mailbox.Name
	}).join('; ');
    
    d.NeedsWork = (d.IsMine &&
		   (d.RequiredAttendees.Attendee.filter(e => { return e.ResponseType.match(/Accept/) }).length < d.RequiredAttendees.Attendee.length)
		   || (d.MyResponseType.match(/unknown/i) || d.MyResponseType.match(/NoResponseReceived/i))
		   || (d.ConflictingMeetingCount > 0)
		  ) ?
	true : false; 

    d.HasConflicts = d.ConflictingMeetingCount > 0 ? true : false;
    
    d.AttendeeStatus = {
	required: d.RequiredAttendees.Attendee.length,
	accepted: d.RequiredAttendees.Attendee.filter(e => { return e.ResponseType.match(/Accept/) }).length,
    }
    d.__proto__ = this.__proto__;
    
    return d;
}

Meeting.prototype.funnyMethod = function(){
    console.log("funny method");
}


var Calendar = function(d) {
    // this = Object.assign(d, object1);;

    // console.log(d.meetings);

    d.meetings
	.map(e => { _fix(e); return e })
	.map(e => { e.IsMine = e.IsOrganizer || e.IsFromMe; return e })
    	.map(e => { e.NeedsWork = !e.MeetingRequestWasSent || e.MyResponseType.match(/NoResponseReceived|Tentative/); return e })
    
    d.__proto__ = this.__proto__;
    
    return d;
}
