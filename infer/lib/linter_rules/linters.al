// Copyright (c) Facebook, Inc. and its affiliates.
//
// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

// DIRECT_ATOMIC_PROPERTY_ACCESS:
// a property declared atomic should not be accessed directly via its ivar
DEFINE-CHECKER DIRECT_ATOMIC_PROPERTY_ACCESS = {

	SET report_when =
	  WHEN
			((NOT context_in_synchronized_block()) AND is_ivar_atomic())
			AND NOT is_method_property_accessor_of_ivar()
			AND NOT is_objc_constructor()
			AND NOT is_objc_dealloc()
		HOLDS-IN-NODE ObjCIvarRefExpr;

  	SET message = "Direct access to ivar %ivar_name% of an atomic property";
  	SET suggestion = "Accessing an ivar of an atomic property makes the property nonatomic.";
	  SET severity = "WARNING";
};
