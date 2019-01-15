/* $Header: /var/lib/cvs/dynare_cpp/sylv/cc/SchurDecomp.cpp,v 1.1.1.1 2004/06/04 13:00:44 kamenik Exp $ */

/* Tag $Name:  $ */

#include "SchurDecomp.hh"

#include <dynlapack.h>

SchurDecomp::SchurDecomp(const SqSylvMatrix &m)
  : q(m.numRows())
{
  lapack_int rows = m.numRows();
  SqSylvMatrix auxt(m);
  lapack_int sdim;
  auto *const wr = new double[rows];
  auto *const wi = new double[rows];
  lapack_int lwork = 6*rows;
  auto *const work = new double[lwork];
  lapack_int info;
  dgees("V", "N", nullptr, &rows, auxt.base(), &rows, &sdim,
        wr, wi, q.base(), &rows,
        work, &lwork, nullptr, &info);
  delete [] work;
  delete [] wi;
  delete [] wr;
  t_storage = std::make_unique<QuasiTriangular>(auxt.base(), rows);
  t = t_storage.get();
}

SchurDecomp::SchurDecomp(const QuasiTriangular &tr)
  : q(tr.numRows()), t_storage{std::make_unique<QuasiTriangular>(tr)}, t{t_storage.get()}
{
  q.setUnit();
}

SchurDecomp::SchurDecomp(QuasiTriangular &tr)
  : q(tr.numRows()), t{&tr}
{
  q.setUnit();
}

int
SchurDecomp::getDim() const
{
  return t->numRows();
}

SchurDecompZero::SchurDecompZero(const GeneralMatrix &m)
  : SchurDecomp(SqSylvMatrix(m, m.numRows()-m.numCols(), 0, m.numCols())),
    ru(m, 0, 0, m.numRows()-m.numCols(), m.numCols())
{
  ru.multRight(getQ());
}

int
SchurDecompZero::getDim() const
{
  return getT().numRows()+ru.numRows();
}
