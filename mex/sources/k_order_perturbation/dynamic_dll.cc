/*
 * Copyright (C) 2008-2017 Dynare Team
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

#include "dynamic_dll.hh"

#include <sstream>

DynamicModelDLL::DynamicModelDLL(const string &modName) throw (DynareException)
{
  string fName;
#if !defined(__CYGWIN32__) && !defined(_WIN32)
  fName = "./";
#endif
  fName += modName + "_dynamic" + MEXEXT;

  try
    {
#if defined(__CYGWIN32__) || defined(_WIN32)
      dynamicHinstance = LoadLibrary(fName.c_str());
      if (dynamicHinstance == NULL)
        throw 1;
      Dynamic = (DynamicDLLFn) GetProcAddress(dynamicHinstance, "Dynamic");
      if (Dynamic == NULL)
        {
          FreeLibrary(dynamicHinstance); // Free the library
          throw 2;
        }
#else // Linux or Mac
      dynamicHinstance = dlopen(fName.c_str(), RTLD_NOW);
      if ((dynamicHinstance == NULL) || dlerror())
        {
          cerr << dlerror() << endl;
          throw 1;
        }
      Dynamic = (DynamicDLLFn) dlsym(dynamicHinstance, "Dynamic");
      if ((Dynamic  == NULL) || dlerror())
        {
          dlclose(dynamicHinstance); // Free the library
          cerr << dlerror() << endl;
          throw 2;
        }
#endif

    }
  catch (int i)
    {
      ostringstream msg;
      msg << "Error when loading " << fName << " (";
      if (i == 1)
        msg << "can't dynamically load the file";
      if (i == 2)
        msg << "can't locate the 'Dynamic' symbol";
      msg << ")";
      throw DynareException(__FILE__, __LINE__, msg.str());
    }
  catch (...)
    {
      throw DynareException(__FILE__, __LINE__, string("Can't find Dynamic function in ") + fName);
    }
}

DynamicModelDLL::~DynamicModelDLL()
{
#if defined(__CYGWIN32__) || defined(_WIN32)
  bool result = FreeLibrary(dynamicHinstance);
  if (result == 0)
    throw DynareException(__FILE__, __LINE__, string("Can't free the *_dynamic DLL"));
#else
  dlclose(dynamicHinstance);
#endif
}

void
DynamicModelDLL::eval(const Vector &y, const Vector &x, const Vector &modParams, const Vector &ySteady, const Vector &xSteady,
                      Vector &residual, TwoDMatrix *g1, TwoDMatrix *g2, TwoDMatrix *g3) throw (DynareException)
{
  Dynamic(y.base(), x.base(), 1, modParams.base(), ySteady.base(), xSteady.base(), 0, residual.base(), g1->base(),
          g2 == NULL ? NULL : g2->base(), g3 == NULL ? NULL : g3->base());
}
