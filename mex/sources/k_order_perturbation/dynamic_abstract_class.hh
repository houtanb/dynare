/*
 * Copyright (C) 2010-2017 Dynare Team
 *
 * This file is part of Dynare.
 *
 * Dynare is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Dynare is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Dynare.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef _DYNAMICMODELAC_HH
#define _DYNAMICMODELAC_HH

#include "k_ord_dynare.hh"

class DynamicModelAC
{
public:
  static double *unpackSparseMatrix(mxArray *sparseMatrix);
  static void copyDoubleIntoTwoDMatData(double *dm, TwoDMatrix *tdm, int rows, int cols);
  virtual void eval(const Vector &y, const Vector &x, const Vector &params, const Vector &ySteady, const Vector &xSteady,
                    Vector &residual, TwoDMatrix *g1, TwoDMatrix *g2, TwoDMatrix *g3) throw (DynareException) = 0;
};
#endif
