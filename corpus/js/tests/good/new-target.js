function F() { return new.target; }
function G() { new.target.x; new.target(); }
class H { constructor() { new.target; } }
