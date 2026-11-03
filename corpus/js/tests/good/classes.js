class A {}
class B extends A {}
class C extends B { constructor() { super(); } }
var D = class {}, E = class Named extends (A) {};
