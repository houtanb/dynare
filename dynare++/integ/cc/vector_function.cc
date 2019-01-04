// Copyright 2005, Ondra Kamenik

#include "vector_function.hh"

#include <dynlapack.h>

#include <cmath>

#include <cstring>
#include <algorithm>

#ifdef __MINGW32__
# define __CROSS_COMPILATION__
#endif

#ifdef __MINGW64__
# define __CROSS_COMPILATION__
#endif

#ifdef __CROSS_COMPILATION__
# define M_PI 3.14159265358979323846
#endif

/* Just an easy constructor of sequence of booleans defaulting to
   change everywhere. */

ParameterSignal::ParameterSignal(int n)
  : data(new bool[n]), num(n)
{
  for (int i = 0; i < num; i++)
    data[i] = true;
}

ParameterSignal::ParameterSignal(const ParameterSignal &sig)
  : data(new bool[sig.num]), num(sig.num)
{
  memcpy(data, sig.data, num);
}

/* This sets |false| (no change) before a given parameter, and |true|
   (change) after the given parameter (including). */

void
ParameterSignal::signalAfter(int l)
{
  for (int i = 0; i < std::min(l, num); i++)
    data[i] = false;
  for (int i = l; i < num; i++)
    data[i] = true;
}

/* This constructs a function set hardcopying also the first. */
VectorFunctionSet::VectorFunctionSet(const VectorFunction &f, int n)
  : funcs(n), first_shallow(false)
{
  for (int i = 0; i < n; i++)
    funcs[i] = f.clone();
}

/* This constructs a function set with shallow copy in the first and
   hard copies in others. */
VectorFunctionSet::VectorFunctionSet(VectorFunction &f, int n)
  : funcs(n), first_shallow(true)
{
  if (n > 0)
    funcs[0] = &f;
  for (int i = 1; i < n; i++)
    funcs[i] = f.clone();
}

/* This deletes the functions. The first is deleted only if it was not
   a shallow copy. */

VectorFunctionSet::~VectorFunctionSet()
{
  unsigned int start = first_shallow ? 1 : 0;
  for (unsigned int i = start; i < funcs.size(); i++)
    delete funcs[i];
}

/* Here we construct the object from the given function $f$ and given
   variance-covariance matrix $\Sigma=$|vcov|. The matrix $A$ is
   calculated as lower triangular and yields $\Sigma=AA^T$. */

GaussConverterFunction::GaussConverterFunction(VectorFunction &f, const GeneralMatrix &vcov)
  : VectorFunction(f), func(&f), delete_flag(false), A(vcov.numRows(), vcov.numRows()),
    multiplier(calcMultiplier())
{
  // todo: raise if |A.numRows() != indim()|
  calcCholeskyFactor(vcov);
}

/* Here we construct the object in the same way, however we mark the
   function as to be deleted. */

GaussConverterFunction::GaussConverterFunction(VectorFunction *f, const GeneralMatrix &vcov)
  : VectorFunction(*f), func(f), delete_flag(true), A(vcov.numRows(), vcov.numRows()),
    multiplier(calcMultiplier())
{
  // todo: raise if |A.numRows() != indim()|
  calcCholeskyFactor(vcov);
}

GaussConverterFunction::GaussConverterFunction(const GaussConverterFunction &f)
  : VectorFunction(f), func(f.func->clone()), delete_flag(true), A(f.A),
    multiplier(f.multiplier)
{
}

/* Here we evaluate the function
   $g(y)={1\over\sqrt{\pi^n}}f\left(\sqrt{2}Ay\right)$. Since the matrix $A$ is lower
   triangular, the change signal for the function $f$ will look like
   $(0,\ldots,0,1,\ldots,1)$ where the first $1$ is in the same position
   as the first change in the given signal |sig| of the input
   $y=$|point|. */

void
GaussConverterFunction::eval(const Vector &point, const ParameterSignal &sig, Vector &out)
{
  ParameterSignal s(sig);
  int i = 0;
  while (i < indim() && !sig[i])
    i++;
  s.signalAfter(i);

  Vector x(indim());
  x.zeros();
  A.multaVec(x, point);
  x.mult(sqrt(2.0));

  func->eval(x, s, out);

  out.mult(multiplier);
}

/* This returns $1\over\sqrt{\pi^n}$. */

double
GaussConverterFunction::calcMultiplier() const
{
  return sqrt(pow(M_PI, -1*indim()));
}

void
GaussConverterFunction::calcCholeskyFactor(const GeneralMatrix &vcov)
{
  A = vcov;

  lapack_int rows = A.numRows();
  for (int i = 0; i < rows; i++)
    for (int j = i+1; j < rows; j++)
      A.get(i, j) = 0.0;

  lapack_int info;
  dpotrf("L", &rows, A.base(), &rows, &info);
  // todo: raise if |info!=1|
}
