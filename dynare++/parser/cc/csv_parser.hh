// Copyright (C) 2007, Ondra Kamenik

// $Id$

#ifndef OGP_CSV_PARSER
#define OGP_CSV_PARSER

namespace ogp
{

  class CSVParserPeer
  {
  public:
    virtual ~CSVParserPeer()
    = default;
    virtual void item(int irow, int icol, const char *str, int length) = 0;
  };

  class CSVParser
  {
  private:
    CSVParserPeer &peer;
    int row;
    int col;
    const char *parsed_string;
  public:
    CSVParser(CSVParserPeer &p)
      : peer(p), row(0), col(0), parsed_string(nullptr)
    {
    }
    CSVParser(const CSVParser &csvp)
       
    = default;
    virtual ~CSVParser()
    = default;

    void csv_error(const char *mes);
    void csv_parse(int length, const char *str);

    void
    nextrow()
    {
      row++; col = 0;
    }
    void
    nextcol()
    {
      col++;
    }
    void
    item(int off, int length)
    {
      peer.item(row, col, parsed_string+off, length);
    }
  };
};

#endif
